import Foundation
import CloudKit
import ExperienceCore

/// Shared guest feed in the CloudKit **public** database.
///
/// The public database has only the default zone. That zone does not support
/// change fetches or atomic batches. Reads are by record ID. Writes are one record at a time.
/// `FeedManifest` (`visit-feed`) lists post IDs. Any signed-in guest may publish.
@MainActor
final class CloudKitFeedRepository: FeedRepository {
    nonisolated static let containerID = "iCloud.com.gardens.experience"

    private let container: CKContainer
    private let database: CKDatabase

    init(container: CKContainer? = nil) {
        let resolved = container ?? CKContainer(identifier: Self.containerID)
        self.container = resolved
        self.database = resolved.publicCloudDatabase
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await within(.seconds(8)) { try await self.container.accountStatus() }
    }

    func userRecordName() async throws -> String {
        try await within(.seconds(8)) { try await self.container.userRecordID().recordName }
    }

    func fetchPosts() async throws -> [Post] {
        try await requireiCloud()
        let manifest = try await loadManifest()
        let ids = Self.recordIDs(Self.stringList(manifest, key: "postIDs"))
        let records = try await fetchRecords(ids: ids)
        return records.compactMap(Self.post(from:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    func publish(_ draft: PostDraft) async throws -> Post {
        var post = try draft.makePost()
        if post.authorRecordName?.isEmpty != false {
            post.authorRecordName = try await userRecordName()
        }
        return try await upload(post)
    }

    /// Saves this post ID. A retry after a partial write updates the same record and list entry.
    /// Returns the post with the CloudKit creator user record name filled in.
    func upload(_ post: Post) async throws -> Post {
        try await requireiCloud()
        var post = post
        if post.authorRecordName?.isEmpty != false {
            post.authorRecordName = try await userRecordName()
        }
        let record = CKRecord(recordType: RecordType.post, recordID: Self.recordID(post.id.uuidString))
        try Self.apply(post, to: record)
        try await saveRecord(record)
        try await commit { manifest in
            Self.append([post.id.uuidString], to: manifest, key: "postIDs")
        }
        try await verifySaved(record.recordID, type: RecordType.post, keys: ["id", "authorRecordName", "createdAt", "text"])
        let saved = try await cloudRecord(for: record.recordID)
        if let creator = saved.creatorUserRecordID?.recordName, !creator.isEmpty {
            post.authorRecordName = creator
        }
        return post
    }

    private enum RecordType {
        static let post = "VisitPost"
        static let manifest = "FeedManifest"
    }

    nonisolated private static let manifestID = CKRecord.ID(
        recordName: "visit-feed",
        zoneID: CKRecordZone.default().zoneID
    )

    nonisolated private static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: CKRecordZone.default().zoneID)
    }

    private func loadManifest() async throws -> CKRecord {
        do {
            return try await cloudRecord(for: Self.manifestID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: RecordType.manifest, recordID: Self.manifestID)
        }
    }

    private func commit(mutate: (CKRecord) -> Void) async throws {
        var lastError: Error = CloudSaveError(message: "Saved the post but couldn’t update the feed list.")
        for _ in 0..<4 {
            let manifest = try await loadManifest()
            mutate(manifest)
            do {
                _ = try await cloudSave(manifest)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private func saveRecord(_ record: CKRecord) async throws {
        do {
            _ = try await cloudSave(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            let existing = try await cloudRecord(for: record.recordID)
            guard existing.recordType == record.recordType else { throw error }
        }
    }

    private func fetchRecords(ids: [CKRecord.ID]) async throws -> [CKRecord] {
        guard !ids.isEmpty else { return [] }
        var records: [CKRecord] = []
        var index = 0
        while index < ids.count {
            let end = min(index + 200, ids.count)
            let batch = try await cloudRecords(for: Array(ids[index..<end]))
            records.append(contentsOf: batch.compactMap { try? $0.get() })
            index = end
        }
        return records
    }

    private func requireiCloud() async throws {
        let status = try await accountStatus()
        guard status == .available else { throw FeedError.notSignedIn }
    }

    private func cloudRecord(for id: CKRecord.ID) async throws -> CKRecord {
        try await within(.seconds(12)) { try await self.database.record(for: id) }
    }

    @discardableResult
    private func cloudSave(_ record: CKRecord) async throws -> CKRecord {
        try await within(.seconds(12)) { try await self.database.save(record) }
    }

    private func cloudRecords(for ids: [CKRecord.ID]) async throws -> [Result<CKRecord, Error>] {
        let map = try await within(.seconds(12)) {
            try await self.database.records(for: ids, desiredKeys: nil)
        }
        return ids.compactMap { map[$0] }
    }

    private func verifySaved(_ id: CKRecord.ID, type: String, keys: [String]) async throws {
        let record = try await cloudRecord(for: id)
        guard record.recordType == type else {
            throw CloudSaveError(message: "Read back \(record.recordType) for \(id.recordName), expected \(type).")
        }
        let missing = keys.filter { record[$0] == nil }
        guard missing.isEmpty else {
            throw CloudSaveError(message: "\(type) is missing \(missing.joined(separator: ", ")) after save.")
        }
    }

    private func within<T>(_ limit: Duration, _ work: @escaping @MainActor () async throws -> T) async throws -> T {
        let gate = CloudResumeGate()
        return try await withCheckedThrowingContinuation { continuation in
            let attempt = Task { @MainActor in
                do {
                    let value = try await work()
                    gate.finish { continuation.resume(returning: value) }
                } catch {
                    gate.finish { continuation.resume(throwing: error) }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                gate.finish {
                    attempt.cancel()
                    continuation.resume(throwing: CloudTimeout())
                }
            }
        }
    }

    private static func apply(_ post: Post, to record: CKRecord) throws {
        record["id"] = post.id.uuidString
        record["text"] = post.text
        record["createdAt"] = post.createdAt
        if let authorRecordName = post.authorRecordName, !authorRecordName.isEmpty {
            record["authorRecordName"] = authorRecordName
        }
        if let data = post.imageData, !data.isEmpty {
            record["image"] = try asset(from: data, name: post.id.uuidString)
        }
    }

    private static func post(from record: CKRecord) -> Post? {
        let idString = record["id"] as? String ?? record.recordID.recordName
        guard let id = UUID(uuidString: idString) else { return nil }
        let storedName = record["authorRecordName"] as? String
        let creatorName = record.creatorUserRecordID?.recordName
        let authorRecordName = [creatorName, storedName].compactMap { $0 }.first { !$0.isEmpty }
        return Post(
            id: id,
            text: record["text"] as? String ?? "",
            imageData: imageData(from: record),
            authorRecordName: authorRecordName,
            createdAt: record["createdAt"] as? Date ?? Date(),
            pendingUpload: false
        )
    }

    private static func imageData(from record: CKRecord) -> Data? {
        guard let asset = record["image"] as? CKAsset, let url = asset.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func asset(from data: Data, name: String) throws -> CKAsset {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("experience-\(name).jpg")
        try data.write(to: url, options: .atomic)
        return CKAsset(fileURL: url)
    }

    private static func stringList(_ record: CKRecord, key: String) -> [String] {
        if let list = record[key] as? [String] { return list }
        if let list = record[key] as? NSArray { return list.compactMap { $0 as? String } }
        return []
    }

    private static func append(_ newIDs: [String], to record: CKRecord, key: String) {
        var ids = stringList(record, key: key)
        for id in newIDs where !ids.contains(id) {
            ids.append(id)
        }
        setList(ids, on: record, key: key)
    }

    /// CloudKit rejects an empty list as the first value of a new field.
    private static func setList(_ ids: [String], on record: CKRecord, key: String) {
        guard !ids.isEmpty else { return }
        record[key] = ids as NSArray
    }

    private static func recordIDs(_ names: [String]) -> [CKRecord.ID] {
        names.map { recordID($0) }
    }
}

private struct CloudSaveError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct CloudTimeout: LocalizedError {
    var errorDescription: String? {
        "iCloud didn’t answer. Posts already on this iPhone stay here — pull to refresh when you have a connection."
    }
}

private final class CloudResumeGate {
    private var finished = false

    func finish(_ body: () -> Void) {
        guard !finished else { return }
        finished = true
        body()
    }
}
