import Foundation
import CloudKit
import GardensCore

/// Shared nursery inventory in the CloudKit **public** database.
///
/// The public database has only the default zone. That zone does not support
/// `CKFetchRecordZoneChanges` (`getChanges`) and does not support atomic batches.
/// Every read is `CKDatabase.record(for:)`. Every write is `CKDatabase.save(_:)`.
/// A single `InventoryManifest` record (`gardens-inventory`) lists catalog and instance IDs.
/// Apple's `Users` type is never written.
@MainActor
final class CloudKitPlantRepository: PlantRepository {
    nonisolated static let containerID = "iCloud.com.gardens.intake"

    private let container: CKContainer
    private let database: CKDatabase
    private var photoCache: [UUID: Data] = [:]

    init(container: CKContainer? = nil) {
        let resolved = container ?? CKContainer(identifier: Self.containerID)
        self.container = resolved
        self.database = resolved.publicCloudDatabase
    }

    func fetchCatalog() async throws -> [PlantCatalogItem] {
        try await requireiCloud()
        let manifest = try await loadManifest()
        let liveIDs = try await catalogIDsInUse(on: manifest)
        let catalogIDs = Self.stringList(manifest, key: "catalogIDs")
        let orphans = catalogIDs.filter { !liveIDs.contains($0) }
        if !orphans.isEmpty {
            // Earlier deletes removed the plants but left the type. Drop those so Existing type matches the list.
            try? await pruneCatalogs(orphans)
        }
        let records = try await fetchRecords(ids: Self.recordIDs(catalogIDs))
        return records.compactMap(Self.catalog(from:))
            .filter { liveIDs.contains($0.id.uuidString) }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func fetchInstances() async throws -> [PlantInstanceDetail] {
        try await requireiCloud()
        let manifest = try await loadManifest()
        let catalogIDs = Self.recordIDs(Self.stringList(manifest, key: "catalogIDs"))
        let instanceIDs = Self.recordIDs(Self.stringList(manifest, key: "instanceIDs"))
        let (loadedCatalogs, loadedInstances) = try await loadListRecords(catalogIDs: catalogIDs, instanceIDs: instanceIDs)
        let catalogByID = Dictionary(uniqueKeysWithValues: loadedCatalogs.compactMap { record -> (UUID, PlantCatalogItem)? in
            guard let item = Self.catalog(from: record) else { return nil }
            return (item.id, item)
        })
        return loadedInstances.compactMap { record in
            guard
                let instance = Self.instance(from: record, photoData: cachedPhoto(on: record)),
                let catalog = catalogByID[instance.catalogItemID]
            else { return nil }
            return PlantInstanceDetail(instance: instance, catalog: catalog)
        }
        .sorted { $0.instance.arrivedOn > $1.instance.arrivedOn }
    }

    private func loadListRecords(
        catalogIDs: [CKRecord.ID],
        instanceIDs: [CKRecord.ID]
    ) async throws -> (catalogs: [CKRecord], instances: [CKRecord]) {
        try await withThrowingTaskGroup(of: (Bool, [CKRecord]).self) { group in
            group.addTask {
                (true, try await self.fetchRecords(ids: catalogIDs, desiredKeys: Self.catalogKeys))
            }
            group.addTask {
                (false, try await self.fetchRecords(ids: instanceIDs, desiredKeys: Self.instanceKeys))
            }
            var catalogs: [CKRecord] = []
            var instances: [CKRecord] = []
            for try await (isCatalog, records) in group {
                if isCatalog {
                    catalogs = records
                } else {
                    instances = records
                }
            }
            return (catalogs, instances)
        }
    }

    func destination(for instanceID: UUID) async throws -> PlantInstanceDestination? {
        try await requireiCloud()
        let instanceRecord: CKRecord
        do {
            instanceRecord = try await cloudRecord(for: Self.recordID(instanceID.uuidString))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        guard let instance = Self.instance(from: instanceRecord, photoData: photoData(from: instanceRecord))
        else { return nil }

        let catalogRecord = try await cloudRecord(for: Self.recordID(instance.catalogItemID.uuidString))
        guard let catalog = Self.catalog(from: catalogRecord) else { return nil }

        let careIDs = Self.stringList(instanceRecord, key: "careEventIDs")
        let careRecords = try await fetchRecords(ids: Self.recordIDs(careIDs))
        let history = careRecords.compactMap(Self.careEvent(from:))

        return PlantInstanceDestination(
            instance: instance,
            catalog: catalog,
            careProfile: catalog.careProfile,
            careHistory: history
        )
    }

    func saveIntake(_ draft: PlantIntakeDraft) async throws -> PlantArrivalBatch {
        try await requireiCloud()
        let catalog = try await resolveCatalog(for: draft)
        let arrivedOn = Calendar.current.startOfDay(for: draft.arrivedOn)
        let vendor = draft.vendor.trimmingCharacters(in: .whitespacesAndNewlines)

        var instanceRecords: [CKRecord] = []
        var details: [PlantInstanceDetail] = []

        for _ in 0..<draft.quantity {
            let instanceID = UUID()
            let record = CKRecord(recordType: RecordType.instance, recordID: Self.recordID(instanceID.uuidString))
            record["id"] = instanceID.uuidString
            record["catalogItemID"] = catalog.id.uuidString
            record["arrivedOn"] = arrivedOn
            record["vendor"] = vendor
            record["createdAt"] = Date()
            if let photoData = draft.photoData {
                record["photo"] = try Self.asset(from: photoData, name: instanceID.uuidString)
                photoCache[instanceID] = photoData
            }
            if let credit = draft.photoCredit, !credit.isEmpty {
                record["photoCredit"] = credit
            }
            instanceRecords.append(record)
            details.append(
                PlantInstanceDetail(
                    instance: PlantInstance(
                        id: instanceID,
                        catalogItemID: catalog.id,
                        arrivedOn: arrivedOn,
                        vendor: vendor,
                        photoData: draft.photoData,
                        photoCredit: draft.photoCredit
                    ),
                    catalog: catalog
                )
            )
        }

        let newIDs = instanceRecords.map(\.recordID.recordName)
        try await commit(saving: instanceRecords) { manifest in
            Self.append(newIDs, to: manifest, key: "instanceIDs")
        }
        for record in instanceRecords {
            try await verifySaved(record.recordID, type: RecordType.instance, keys: ["catalogItemID", "vendor", "arrivedOn"])
        }
        return PlantArrivalBatch(catalog: catalog, instances: details)
    }

    func addCareEvent(_ event: CareEvent) async throws {
        try await requireiCloud()
        let care = CKRecord(recordType: RecordType.careEvent, recordID: Self.recordID(event.id.uuidString))
        care["id"] = event.id.uuidString
        care["instanceID"] = event.instanceID.uuidString
        care["kind"] = event.kind.rawValue
        care["performedAt"] = event.performedAt
        care["wateringObservation"] = event.wateringObservation
        care["healthObservation"] = event.healthObservation
        care["notes"] = event.notes
        try await saveRecord(care)

        var lastError: Error = CloudSaveError(message: "Saved the care note but couldn’t attach it to the plant.")
        for _ in 0..<4 {
            let instanceRecord: CKRecord
            do {
                instanceRecord = try await cloudRecord(for: Self.recordID(event.instanceID.uuidString))
            } catch let error as CKError where error.code == .unknownItem {
                throw RepositoryError.instanceNotFound
            }
            var careIDs = Self.stringList(instanceRecord, key: "careEventIDs")
            if !careIDs.contains(event.id.uuidString) {
                careIDs.append(event.id.uuidString)
            }
            Self.setList(careIDs, on: instanceRecord, key: "careEventIDs")
            do {
                _ = try await cloudSave(instanceRecord)
                try await verifySaved(care.recordID, type: RecordType.careEvent, keys: ["instanceID", "kind", "performedAt"])
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    func updateInstancePhoto(instanceID: UUID, photoData: Data?, photoCredit: String?) async throws {
        try await requireiCloud()
        var lastError: Error = RepositoryError.instanceNotFound
        for _ in 0..<4 {
            let record: CKRecord
            do {
                record = try await cloudRecord(for: Self.recordID(instanceID.uuidString))
            } catch let error as CKError where error.code == .unknownItem {
                throw RepositoryError.instanceNotFound
            }
            if let photoData {
                record["photo"] = try Self.asset(from: photoData, name: instanceID.uuidString)
            } else {
                record["photo"] = nil
            }
            if let photoCredit, !photoCredit.isEmpty, photoData != nil {
                record["photoCredit"] = photoCredit
            } else {
                record["photoCredit"] = nil
            }
            do {
                _ = try await cloudSave(record)
                if let photoData {
                    photoCache[instanceID] = photoData
                    try await verifySaved(record.recordID, type: RecordType.instance, keys: ["photo"])
                } else {
                    photoCache.removeValue(forKey: instanceID)
                }
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    func deleteInstance(instanceID: UUID) async throws {
        try await requireiCloud()
        let record: CKRecord
        do {
            record = try await cloudRecord(for: Self.recordID(instanceID.uuidString))
        } catch let error as CKError where error.code == .unknownItem {
            throw RepositoryError.instanceNotFound
        }
        let catalogID = record["catalogItemID"] as? String
        let careIDs = Self.stringList(record, key: "careEventIDs")
        for careID in careIDs {
            let careRecordID = Self.recordID(careID)
            try await deleteIfPresent(careRecordID)
            try await assertDeleted(careRecordID, what: "care note")
        }
        try await deleteIfPresent(record.recordID)
        try await assertDeleted(record.recordID, what: "plant")
        photoCache.removeValue(forKey: instanceID)

        var dropCatalog: String?
        if let catalogID {
            let manifest = try await loadManifest()
            let others = Self.stringList(manifest, key: "instanceIDs").filter { $0 != instanceID.uuidString }
            let remaining = try await fetchRecords(ids: Self.recordIDs(others))
            let stillUsed = remaining.contains { ($0["catalogItemID"] as? String) == catalogID }
            if !stillUsed {
                let catalogRecordID = Self.recordID(catalogID)
                try await deleteIfPresent(catalogRecordID)
                try await assertDeleted(catalogRecordID, what: "plant type")
                dropCatalog = catalogID
            }
        }

        for _ in 0..<4 {
            let manifest = try await loadManifest()
            guard manifest.recordChangeTag != nil else { return }
            Self.remove([instanceID.uuidString], from: manifest, key: "instanceIDs")
            if let dropCatalog {
                Self.remove([dropCatalog], from: manifest, key: "catalogIDs")
            }
            do {
                _ = try await cloudSave(manifest)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            } catch {
                // The records are already gone. A later fetch skips a missing ID.
                return
            }
        }
    }

    func updateCareProfile(catalogItemID: UUID, profile: PlantCareProfile) async throws {
        try await requireiCloud()
        var lastError: Error = RepositoryError.catalogNotFound
        for _ in 0..<4 {
            let record: CKRecord
            do {
                record = try await cloudRecord(for: Self.recordID(catalogItemID.uuidString))
            } catch {
                throw RepositoryError.catalogNotFound
            }
            record["careInstructions"] = profile.careInstructions
            record["wateringCheckGuidance"] = profile.wateringCheckGuidance
            record["healthCheckGuidance"] = profile.healthCheckGuidance
            do {
                _ = try await cloudSave(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    func referencePhoto(for catalogItemID: UUID) async throws -> Data? {
        try await requireiCloud()
        let manifest = try await loadManifest()
        let records = try await fetchRecords(ids: Self.recordIDs(Self.stringList(manifest, key: "instanceIDs")))
            .filter { ($0["catalogItemID"] as? String) == catalogItemID.uuidString }
            .sorted { lhs, rhs in
                (lhs["createdAt"] as? Date ?? .distantPast) > (rhs["createdAt"] as? Date ?? .distantPast)
            }
        for record in records.prefix(12) {
            if let data = photoData(from: record) { return data }
        }
        return nil
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await within(.seconds(8)) { try await self.container.accountStatus() }
    }

    func userRecordName() async throws -> String {
        try await within(.seconds(8)) { try await self.container.userRecordID().recordName }
    }

    // MARK: - Manifest

    private enum RecordType {
        static let catalog = "CatalogItem"
        static let instance = "PlantInstance"
        static let careEvent = "CareEvent"
        static let manifest = "InventoryManifest"
    }

    /// Stable id in the public default zone. Fetch-by-ID does not need a queryable index.
    nonisolated private static let manifestID = CKRecord.ID(
        recordName: "gardens-inventory",
        zoneID: CKRecordZone.default().zoneID
    )

    /// Public default zone. Custom zones are not allowed in the public database.
    nonisolated private static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: CKRecordZone.default().zoneID)
    }

    private func loadManifest() async throws -> CKRecord {
        do {
            return try await cloudRecord(for: Self.manifestID)
        } catch let error as CKError where error.code == .unknownItem {
            // Leave list fields unset. CloudKit rejects an empty list as the first value of a new field.
            return CKRecord(recordType: RecordType.manifest, recordID: Self.manifestID)
        }
    }

    /// Saves each data record on its own, then appends their IDs to the manifest.
    /// The default zone ignores atomic batches, so the manifest update is a separate save and retries on conflict.
    private func commit(saving extra: [CKRecord], mutate: (CKRecord) -> Void) async throws {
        for record in extra {
            try await saveRecord(record)
        }
        var lastError: Error = CloudSaveError(message: "Saved the plant records but couldn’t update the inventory list.")
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

    /// Insert, or accept the record if this ID was already saved (a retry after a successful write).
    private func saveRecord(_ record: CKRecord) async throws {
        do {
            _ = try await cloudSave(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            let existing = try await cloudRecord(for: record.recordID)
            guard existing.recordType == record.recordType else { throw error }
        }
    }

    private func resolveCatalog(for draft: PlantIntakeDraft) async throws -> PlantCatalogItem {
        switch draft.catalogMode {
        case .existingType(let catalogItemID):
            let record = try await cloudRecord(for: Self.recordID(catalogItemID.uuidString))
            guard let item = Self.catalog(from: record) else { throw RepositoryError.catalogNotFound }
            return item

        case .newOrMatchType:
            let existing = try await fetchCatalog()
            if let match = PlantCatalogMatcher.findExisting(name: draft.name, genus: draft.genus, in: existing) {
                return match
            }
            let item = PlantCatalogItem(name: draft.name, genus: draft.genus, careProfile: draft.careProfile)
            let recordID = Self.recordID(item.id.uuidString)
            let record = CKRecord(recordType: RecordType.catalog, recordID: recordID)
            Self.apply(item, to: record)
            try await commit(saving: [record]) { manifest in
                Self.append([item.id.uuidString], to: manifest, key: "catalogIDs")
            }
            try await verifySaved(recordID, type: RecordType.catalog, keys: ["name", "genus", "createdAt"])
            return item
        }
    }

    private func catalogIDsInUse(on manifest: CKRecord) async throws -> Set<String> {
        let records = try await fetchRecords(
            ids: Self.recordIDs(Self.stringList(manifest, key: "instanceIDs")),
            desiredKeys: ["catalogItemID"]
        )
        return Set(records.compactMap { $0["catalogItemID"] as? String })
    }

    /// Removes catalog IDs that no remaining plant references. Recomputes on conflict so a new arrival is not deleted.
    private func pruneCatalogs(_ orphans: [String]) async throws {
        guard !orphans.isEmpty else { return }
        for _ in 0..<4 {
            let manifest = try await loadManifest()
            guard manifest.recordChangeTag != nil else { return }
            let live = try await catalogIDsInUse(on: manifest)
            let drop = Self.stringList(manifest, key: "catalogIDs").filter { orphans.contains($0) && !live.contains($0) }
            if drop.isEmpty { return }
            Self.remove(drop, from: manifest, key: "catalogIDs")
            do {
                _ = try await cloudSave(manifest)
                for id in drop {
                    try await deleteIfPresent(Self.recordID(id))
                }
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            }
        }
    }

    /// JPEG bytes for the list, after the names are already on screen.
    func fetchPhotoData(for instanceIDs: [UUID]) async -> [UUID: Data] {
        guard !instanceIDs.isEmpty else { return [:] }
        let ids = instanceIDs.map { Self.recordID($0.uuidString) }
        guard let records = try? await fetchChunk(ids, desiredKeys: ["id", "photo"]) else { return [:] }
        var photos: [UUID: Data] = [:]
        for record in records {
            guard let data = photoData(from: record) else { continue }
            let name = (record["id"] as? String) ?? record.recordID.recordName
            if let id = UUID(uuidString: name) {
                photos[id] = data
            }
        }
        return photos
    }

    /// Fetch-by-ID, several batches at once. Public AppDefaultZone has no query and no change token.
    private func fetchRecords(ids: [CKRecord.ID], desiredKeys: [CKRecord.FieldKey]? = nil) async throws -> [CKRecord] {
        let chunks = Self.chunks(of: ids, size: 40)
        guard !chunks.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: [CKRecord].self) { group in
            var next = 0
            let width = min(4, chunks.count)
            for _ in 0..<width {
                let chunk = chunks[next]
                next += 1
                group.addTask { try await self.fetchChunk(chunk, desiredKeys: desiredKeys) }
            }
            var collected: [CKRecord] = []
            collected.reserveCapacity(ids.count)
            while let batch = try await group.next() {
                collected.append(contentsOf: batch)
                if next < chunks.count {
                    let chunk = chunks[next]
                    next += 1
                    group.addTask { try await self.fetchChunk(chunk, desiredKeys: desiredKeys) }
                }
            }
            return collected
        }
    }

    private func fetchChunk(_ ids: [CKRecord.ID], desiredKeys: [CKRecord.FieldKey]?) async throws -> [CKRecord] {
        guard !ids.isEmpty else { return [] }
        do {
            let results = try await cloudRecords(for: ids, desiredKeys: desiredKeys)
            var records: [CKRecord] = []
            records.reserveCapacity(results.count)
            for result in results.values {
                switch result {
                case .success(let record):
                    records.append(record)
                case .failure(let error as CKError) where error.code == .unknownItem:
                    continue
                case .failure(let error):
                    throw error
                }
            }
            return records
        } catch let error as CKError where error.code == .partialFailure || error.code == .limitExceeded {
            return try await fetchIndividually(ids)
        }
    }

    private func fetchIndividually(_ ids: [CKRecord.ID]) async throws -> [CKRecord] {
        try await withThrowingTaskGroup(of: CKRecord?.self) { group in
            for id in ids {
                group.addTask {
                    do {
                        return try await self.cloudRecord(for: id)
                    } catch let error as CKError where error.code == .unknownItem {
                        return nil
                    }
                }
            }
            var records: [CKRecord] = []
            for try await record in group {
                if let record { records.append(record) }
            }
            return records
        }
    }

    private static func chunks(of ids: [CKRecord.ID], size: Int) -> [[CKRecord.ID]] {
        guard size > 0, !ids.isEmpty else { return [] }
        return stride(from: 0, to: ids.count, by: size).map { start in
            Array(ids[start..<min(start + size, ids.count)])
        }
    }

    private static let catalogKeys = [
        "id", "name", "genus", "careInstructions", "wateringCheckGuidance", "healthCheckGuidance", "createdAt"
    ]
    private static let instanceKeys = [
        "id", "catalogItemID", "arrivedOn", "vendor", "photoCredit", "createdAt"
    ]

    private func verifySaved(_ id: CKRecord.ID, type: String, keys: [String]) async throws {
        let record: CKRecord
        do {
            record = try await cloudRecord(for: id)
        } catch {
            throw CloudSaveError(message: "Saved \(type) but couldn’t read it back: \(error.localizedDescription)")
        }
        guard record.recordType == type else {
            throw CloudSaveError(message: "Read back \(record.recordType) for \(id.recordName), expected \(type).")
        }
        let missing = keys.filter { record[$0] == nil }
        guard missing.isEmpty else {
            throw CloudSaveError(message: "\(type) \(id.recordName) is missing \(missing.joined(separator: ", ")) after save.")
        }
    }

    /// CloudKit’s own request timer retries for a long time. Give up so the screen can move on.
    private func cloudRecord(for id: CKRecord.ID) async throws -> CKRecord {
        try await within(.seconds(12)) { try await self.database.record(for: id) }
    }

    @discardableResult
    private func cloudSave(_ record: CKRecord) async throws -> CKRecord {
        try await within(.seconds(12)) { try await self.database.save(record) }
    }

    private func cloudDelete(_ id: CKRecord.ID) async throws {
        try await within(.seconds(12)) { _ = try await self.database.deleteRecord(withID: id) }
    }

    private func cloudRecords(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        try await within(.seconds(12)) { try await self.database.records(for: ids, desiredKeys: desiredKeys) }
    }

    private func within<T>(_ limit: Duration, _ work: @escaping @MainActor () async throws -> T) async throws -> T {
        let gate = CloudResumeGate()
        return try await withCheckedThrowingContinuation { continuation in
            let attempt = Task { @MainActor in
                do {
                    let value = try await work()
                    gate.finish {
                        continuation.resume(returning: value)
                    }
                } catch {
                    gate.finish {
                        continuation.resume(throwing: error)
                    }
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

    private func requireiCloud() async throws {
        let status = try await accountStatus()
        guard status == .available else { throw RepositoryError.notSignedIn }
    }

    private static func stringList(_ record: CKRecord, key: String) -> [String] {
        if let list = record[key] as? [String] { return list }
        if let list = record[key] as? NSArray {
            return list.compactMap { $0 as? String }
        }
        return []
    }

    private static func append(_ newIDs: [String], to record: CKRecord, key: String) {
        var ids = stringList(record, key: key)
        for id in newIDs where !ids.contains(id) {
            ids.append(id)
        }
        setList(ids, on: record, key: key)
    }

    /// CloudKit returns "cannot use an empty list to initialize a new field" if the first write of a list is empty.
    private static func setList(_ ids: [String], on record: CKRecord, key: String) {
        guard !ids.isEmpty else { return }
        record[key] = ids as NSArray
    }

    /// Drops IDs from a list. An empty result clears the field instead of writing `[]`.
    private static func remove(_ idsToDrop: [String], from record: CKRecord, key: String) {
        let drop = Set(idsToDrop)
        let remaining = stringList(record, key: key).filter { !drop.contains($0) }
        if remaining.isEmpty {
            record[key] = nil
        } else {
            record[key] = remaining as NSArray
        }
    }

    private func deleteIfPresent(_ id: CKRecord.ID) async throws {
        do {
            _ = try await cloudDelete(id)
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch let error as CKError where error.code == .permissionFailure || error.code == .notAuthenticated {
            throw CloudSaveError(
                message: "iCloud refused to delete this record (\(error.localizedDescription)). In CloudKit Console → Schema → Security Roles, Creator needs Write on CatalogItem, PlantInstance, CareEvent, and InventoryManifest."
            )
        }
    }

    /// `record(for:)` returns unknownItem once CloudKit has actually deleted the record.
    private func assertDeleted(_ id: CKRecord.ID, what: String) async throws {
        do {
            _ = try await cloudRecord(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            throw error
        }
        throw CloudSaveError(message: "iCloud still has this \(what) after delete.")
    }

    private static func recordIDs(_ names: [String]) -> [CKRecord.ID] {
        names.map { recordID($0) }
    }

    private func cachedPhoto(on record: CKRecord) -> Data? {
        let name = (record["id"] as? String) ?? record.recordID.recordName
        guard let id = UUID(uuidString: name) else { return nil }
        return photoCache[id]
    }

    private func photoData(from record: CKRecord) -> Data? {
        if let idString = record["id"] as? String, let id = UUID(uuidString: idString), let cached = photoCache[id] {
            return cached
        }
        guard let asset = record["photo"] as? CKAsset, let url = asset.fileURL, let data = try? Data(contentsOf: url) else {
            return nil
        }
        if let idString = record["id"] as? String, let id = UUID(uuidString: idString) {
            photoCache[id] = data
        }
        return data
    }

    private static func asset(from data: Data, name: String) throws -> CKAsset {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gardens-\(name).jpg")
        try data.write(to: url, options: .atomic)
        return CKAsset(fileURL: url)
    }

    private static func apply(_ item: PlantCatalogItem, to record: CKRecord) {
        record["id"] = item.id.uuidString
        record["name"] = item.name
        record["genus"] = item.genus
        record["careInstructions"] = item.careProfile.careInstructions
        record["wateringCheckGuidance"] = item.careProfile.wateringCheckGuidance
        record["healthCheckGuidance"] = item.careProfile.healthCheckGuidance
        record["createdAt"] = item.createdAt
    }

    private static func catalog(from record: CKRecord) -> PlantCatalogItem? {
        guard
            let idString = record["id"] as? String ?? Optional(record.recordID.recordName),
            let id = UUID(uuidString: idString)
        else { return nil }
        return PlantCatalogItem(
            id: id,
            name: record["name"] as? String ?? "",
            genus: record["genus"] as? String ?? "",
            careProfile: PlantCareProfile(
                careInstructions: record["careInstructions"] as? String ?? "",
                wateringCheckGuidance: record["wateringCheckGuidance"] as? String ?? "",
                healthCheckGuidance: record["healthCheckGuidance"] as? String ?? ""
            ),
            createdAt: record["createdAt"] as? Date ?? Date()
        )
    }

    private static func instance(from record: CKRecord, photoData: Data?) -> PlantInstance? {
        guard
            let idString = record["id"] as? String ?? Optional(record.recordID.recordName),
            let id = UUID(uuidString: idString),
            let catalogString = record["catalogItemID"] as? String,
            let catalogID = UUID(uuidString: catalogString)
        else { return nil }
        return PlantInstance(
            id: id,
            catalogItemID: catalogID,
            arrivedOn: record["arrivedOn"] as? Date ?? Date(),
            vendor: record["vendor"] as? String ?? "",
            photoData: photoData,
            photoCredit: record["photoCredit"] as? String,
            createdAt: record["createdAt"] as? Date ?? Date()
        )
    }

    private static func careEvent(from record: CKRecord) -> CareEvent? {
        guard
            let idString = record["id"] as? String ?? Optional(record.recordID.recordName),
            let id = UUID(uuidString: idString),
            let instanceString = record["instanceID"] as? String,
            let instanceID = UUID(uuidString: instanceString),
            let kindRaw = record["kind"] as? String,
            let kind = CareEventKind(rawValue: kindRaw)
        else { return nil }
        return CareEvent(
            id: id,
            instanceID: instanceID,
            kind: kind,
            performedAt: record["performedAt"] as? Date ?? Date(),
            wateringObservation: record["wateringObservation"] as? String ?? "",
            healthObservation: record["healthObservation"] as? String ?? "",
            notes: record["notes"] as? String ?? ""
        )
    }
}

private struct CloudSaveError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct CloudTimeout: LocalizedError {
    var errorDescription: String? {
        "iCloud didn’t answer. The list stays as it is — pull to refresh when you have a connection."
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
