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
        let records = try await fetchRecords(ids: Self.recordIDs(Self.stringList(manifest, key: "catalogIDs")))
        return records.compactMap(Self.catalog(from:)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func fetchInstances() async throws -> [PlantInstanceDetail] {
        try await requireiCloud()
        let manifest = try await loadManifest()
        let catalogRecords = try await fetchRecords(ids: Self.recordIDs(Self.stringList(manifest, key: "catalogIDs")))
        let instanceRecords = try await fetchRecords(ids: Self.recordIDs(Self.stringList(manifest, key: "instanceIDs")))
        let catalogByID = Dictionary(uniqueKeysWithValues: catalogRecords.compactMap { record -> (UUID, PlantCatalogItem)? in
            guard let item = Self.catalog(from: record) else { return nil }
            return (item.id, item)
        })
        return instanceRecords.compactMap { record in
            guard
                let instance = Self.instance(from: record, photoData: photoData(from: record)),
                let catalog = catalogByID[instance.catalogItemID]
            else { return nil }
            return PlantInstanceDetail(instance: instance, catalog: catalog)
        }
        .sorted { $0.instance.arrivedOn > $1.instance.arrivedOn }
    }

    func destination(for instanceID: UUID) async throws -> PlantInstanceDestination? {
        try await requireiCloud()
        let instanceRecord: CKRecord
        do {
            instanceRecord = try await database.record(for: Self.recordID(instanceID.uuidString))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        guard let instance = Self.instance(from: instanceRecord, photoData: photoData(from: instanceRecord))
        else { return nil }

        let catalogRecord = try await database.record(for: Self.recordID(instance.catalogItemID.uuidString))
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
            instanceRecords.append(record)
            details.append(
                PlantInstanceDetail(
                    instance: PlantInstance(
                        id: instanceID,
                        catalogItemID: catalog.id,
                        arrivedOn: arrivedOn,
                        vendor: vendor,
                        photoData: draft.photoData
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
                instanceRecord = try await database.record(for: Self.recordID(event.instanceID.uuidString))
            } catch let error as CKError where error.code == .unknownItem {
                throw RepositoryError.instanceNotFound
            }
            var careIDs = Self.stringList(instanceRecord, key: "careEventIDs")
            if !careIDs.contains(event.id.uuidString) {
                careIDs.append(event.id.uuidString)
            }
            Self.setList(careIDs, on: instanceRecord, key: "careEventIDs")
            do {
                _ = try await database.save(instanceRecord)
                try await verifySaved(care.recordID, type: RecordType.careEvent, keys: ["instanceID", "kind", "performedAt"])
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    func updateCareProfile(catalogItemID: UUID, profile: PlantCareProfile) async throws {
        try await requireiCloud()
        var lastError: Error = RepositoryError.catalogNotFound
        for _ in 0..<4 {
            let record: CKRecord
            do {
                record = try await database.record(for: Self.recordID(catalogItemID.uuidString))
            } catch {
                throw RepositoryError.catalogNotFound
            }
            record["careInstructions"] = profile.careInstructions
            record["wateringCheckGuidance"] = profile.wateringCheckGuidance
            record["healthCheckGuidance"] = profile.healthCheckGuidance
            do {
                _ = try await database.save(record)
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
        try await container.accountStatus()
    }

    func userRecordName() async throws -> String {
        try await container.userRecordID().recordName
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
            return try await database.record(for: Self.manifestID)
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
                _ = try await database.save(manifest)
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
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            let existing = try await database.record(for: record.recordID)
            guard existing.recordType == record.recordType else { throw error }
        }
    }

    private func resolveCatalog(for draft: PlantIntakeDraft) async throws -> PlantCatalogItem {
        switch draft.catalogMode {
        case .existingType(let catalogItemID):
            let record = try await database.record(for: Self.recordID(catalogItemID.uuidString))
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

    private func fetchRecords(ids: [CKRecord.ID]) async throws -> [CKRecord] {
        var collected: [CKRecord] = []
        collected.reserveCapacity(ids.count)
        for id in ids {
            do {
                collected.append(try await database.record(for: id))
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
        return collected
    }

    private func verifySaved(_ id: CKRecord.ID, type: String, keys: [String]) async throws {
        let record: CKRecord
        do {
            record = try await database.record(for: id)
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

    private func requireiCloud() async throws {
        let status = try await container.accountStatus()
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

    private static func recordIDs(_ names: [String]) -> [CKRecord.ID] {
        names.map { recordID($0) }
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
