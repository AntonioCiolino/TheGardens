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

    /// Jen’s note. One record named `message-of-the-day`, authored as `gardens-app`.
    /// Missing records are seeded. This id is not added to the guest feed list.
    func fetchOrSeedMessageOfTheDay() async throws -> Post {
        try await requireiCloud()
        let recordID = Self.recordID(AppVoice.messageRecordName)
        do {
            let record = try await cloudRecord(for: recordID)
            return Self.message(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            let seed = AppVoice.seededMessage()
            let record = CKRecord(recordType: RecordType.post, recordID: recordID)
            try Self.apply(seed, to: record)
            try await saveRecord(record)
            return seed
        }
    }

    private static func message(from record: CKRecord) -> Post {
        let text = (record["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = text.isEmpty ? AppVoice.seededCareNote : text
        let signed = (record["authorName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Post(
            id: AppVoice.messageID,
            text: note,
            authorName: signed.isEmpty ? AppVoice.authorName : signed,
            authorRecordName: AppVoice.recordName,
            createdAt: record["createdAt"] as? Date ?? Date(),
            pendingUpload: false
        )
    }

    func userRecordName() async throws -> String {
        try await within(.seconds(8)) { try await self.container.userRecordID().recordName }
    }

    /// Fence list. One record named `garden-places`. The bundled JSON is written only when that record is missing.
    func fetchOrSeedPlaces(_ seed: [GardenPlace]) async throws -> [GardenPlace] {
        try await requireiCloud()
        let recordID = Self.recordID("garden-places")
        do {
            let record = try await cloudRecord(for: recordID)
            guard let places = Self.places(from: record), !places.isEmpty else {
                throw CloudSaveError(message: "garden-places has no place list.")
            }
            return places
        } catch let error as CKError where error.code == .unknownItem {
            let record = CKRecord(recordType: RecordType.catalog, recordID: recordID)
            record["placesJSON"] = try Self.placesJSON(seed)
            try await saveRecord(record)
            return seed
        }
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

    /// Stores a guest's report in the public database so the operator can review and remove the post.
    /// Reports are their own records, listed in the `visit-reports` manifest.
    func submitReport(_ report: FeedReport) async throws {
        try await requireiCloud()
        var report = report
        if report.reporterRecordName?.isEmpty != false {
            report.reporterRecordName = try? await userRecordName()
        }
        let record = CKRecord(recordType: RecordType.report, recordID: Self.recordID("report-\(report.id.uuidString)"))
        record["id"] = report.id.uuidString
        record["postID"] = report.postID.uuidString
        record["reason"] = report.reason.rawValue
        record["createdAt"] = report.createdAt
        if let author = report.authorRecordName, !author.isEmpty {
            record["authorRecordName"] = author
        }
        if let reporter = report.reporterRecordName, !reporter.isEmpty {
            record["reporterRecordName"] = reporter
        }
        try await saveRecord(record)
        try await commitReports { manifest in
            Self.append([report.id.uuidString], to: manifest, key: "reportIDs")
        }
    }

    private enum RecordType {
        static let post = "VisitPost"
        static let manifest = "FeedManifest"
        static let catalog = "GardenCatalog"
        static let report = "FeedReport"
        static let roster = "ModeratorRoster"
    }

    /// Number of distinct reports per post id, read from the `visit-reports` manifest.
    /// Used for automatic hiding once a post crosses the report threshold.
    func fetchReportCounts() async throws -> [UUID: Int] {
        try await requireiCloud()
        let manifest = try await loadReportsManifest()
        let names = Self.stringList(manifest, key: "reportIDs").map { "report-\($0)" }
        guard !names.isEmpty else { return [:] }
        let records = try await fetchRecords(ids: Self.recordIDs(names))
        var counts: [UUID: Int] = [:]
        for record in records {
            guard let postIDString = record["postID"] as? String,
                  let postID = UUID(uuidString: postIDString) else { continue }
            counts[postID, default: 0] += 1
        }
        return counts
    }

    /// The shared moderator roster. Seeds it from `ModerationPolicy.seedModeratorRecordNames`
    /// the first time the record is missing.
    func fetchOrSeedModerators() async throws -> ModeratorRoster {
        try await requireiCloud()
        let recordID = Self.recordID(ModerationPolicy.rosterRecordName)
        do {
            let record = try await cloudRecord(for: recordID)
            return ModeratorRoster(recordNames: Set(Self.stringList(record, key: "userRecordNames")))
        } catch let error as CKError where error.code == .unknownItem {
            let seeds = ModerationPolicy.seedModeratorRecordNames.filter { !$0.isEmpty }
            let record = CKRecord(recordType: RecordType.roster, recordID: recordID)
            if !seeds.isEmpty {
                Self.setList(seeds, on: record, key: "userRecordNames")
                try await saveRecord(record)
            }
            return ModeratorRoster(recordNames: Set(seeds))
        }
    }

    /// Adds a user record name to the shared moderator roster. Retries on concurrent edits.
    func addModerator(userRecordName: String) async throws -> ModeratorRoster {
        try await requireiCloud()
        let recordID = Self.recordID(ModerationPolicy.rosterRecordName)
        var lastError: Error = CloudSaveError(message: "Couldn’t update the moderator list.")
        for _ in 0..<4 {
            let record: CKRecord
            do {
                record = try await cloudRecord(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: RecordType.roster, recordID: recordID)
            }
            Self.append([userRecordName], to: record, key: "userRecordNames")
            do {
                _ = try await cloudSave(record)
                return ModeratorRoster(recordNames: Set(Self.stringList(record, key: "userRecordNames")))
            } catch let error as CKError where error.code == .serverRecordChanged {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    /// Operator takedown: hard-deletes a post record and removes it from the feed manifest.
    /// After this, the post is gone for every guest on their next refresh.
    func deletePost(id: UUID) async throws {
        try await requireiCloud()
        try await commit { manifest in
            Self.remove([id.uuidString], from: manifest, key: "postIDs")
        }
        do {
            try await within(.seconds(12)) { _ = try await self.database.deleteRecord(withID: Self.recordID(id.uuidString)) }
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone — removing it from the manifest is enough.
        }
    }

    /// Operator "keep": clears every report filed against a post so it drops below the
    /// auto-hide threshold and returns to the public feed. The post itself is untouched.
    /// Deletes the report records and removes their IDs from the reports manifest.
    func clearReports(forPostID postID: UUID) async throws {
        try await requireiCloud()
        let manifest = try await loadReportsManifest()
        let reportIDs = Self.stringList(manifest, key: "reportIDs")
        guard !reportIDs.isEmpty else { return }

        // Find the report records that belong to this post.
        let records = try await fetchRecords(ids: Self.recordIDs(reportIDs.map { "report-\($0)" }))
        let matchingReportIDs = records.compactMap { record -> String? in
            guard (record["postID"] as? String) == postID.uuidString else { return nil }
            return record["id"] as? String
        }
        guard !matchingReportIDs.isEmpty else { return }

        // Drop the IDs from the manifest first, so a failed delete can't leave a dangling count.
        try await commitReports { manifest in
            Self.remove(matchingReportIDs, from: manifest, key: "reportIDs")
        }

        for reportID in matchingReportIDs {
            let recordID = Self.recordID("report-\(reportID)")
            do {
                try await within(.seconds(12)) { _ = try await self.database.deleteRecord(withID: recordID) }
            } catch let error as CKError where error.code == .unknownItem {
                // Already gone — dropping it from the manifest is enough.
            }
        }
    }

    private static func placesJSON(_ places: [GardenPlace]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(places), as: UTF8.self)
    }

    private static func places(from record: CKRecord) -> [GardenPlace]? {
        guard let json = record["placesJSON"] as? String, let data = json.data(using: .utf8) else { return nil }
        return try? GardenPlaceCatalog.load(from: data)
    }

    nonisolated private static let manifestID = CKRecord.ID(
        recordName: "visit-feed",
        zoneID: CKRecordZone.default().zoneID
    )

    nonisolated private static let reportsManifestID = CKRecord.ID(
        recordName: "visit-reports",
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

    private func loadReportsManifest() async throws -> CKRecord {
        do {
            return try await cloudRecord(for: Self.reportsManifestID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: RecordType.manifest, recordID: Self.reportsManifestID)
        }
    }

    private func commitReports(mutate: (CKRecord) -> Void) async throws {
        var lastError: Error = CloudSaveError(message: "Saved the report but couldn’t update the report list.")
        for _ in 0..<4 {
            let manifest = try await loadReportsManifest()
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
        if !post.authorName.isEmpty {
            record["authorName"] = post.authorName
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
        let authorRecordName = (storedName?.isEmpty == false) ? storedName : creatorName
        return Post(
            id: id,
            text: record["text"] as? String ?? "",
            imageData: imageData(from: record),
            authorName: record["authorName"] as? String ?? "",
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

    private static func remove(_ dropIDs: [String], from record: CKRecord, key: String) {
        let drop = Set(dropIDs)
        let ids = stringList(record, key: key).filter { !drop.contains($0) }
        // An emptied list is written as an empty array so the removal persists.
        record[key] = ids as NSArray
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
