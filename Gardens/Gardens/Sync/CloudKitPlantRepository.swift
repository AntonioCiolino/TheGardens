import Foundation
import CloudKit
import GardensCore

/// Thread-safe bag for CloudKit callbacks (they are not on the main actor).
private final class CloudKitRecordBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CKRecord] = []

    func append(_ record: CKRecord) {
        lock.lock()
        items.append(record)
        lock.unlock()
    }

    func all() -> [CKRecord] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

/// Shared nursery inventory in the **CloudKit public database** (record-per-plant).
/// Reads use zone changes + record IDs so fields do not need to be queryable.
/// The system `Users` record type is left alone (Apple creates it with no custom fields).
@MainActor
final class CloudKitPlantRepository: PlantRepository {
    nonisolated static let containerID = "iCloud.com.gardens.intake"

    private let container: CKContainer
    private let database: CKDatabase
    private var photoCache: [UUID: Data] = [:]

    init(container: CKContainer? = nil) {
        let resolved = container ?? CKContainer(identifier: Self.containerID)
        self.container = resolved
        // Public DB = one shared inventory for everyone who uses this app with iCloud.
        self.database = resolved.publicCloudDatabase
    }

    func fetchCatalog() async throws -> [PlantCatalogItem] {
        try await requireiCloud()
        let records = try await ownedRecords(ofType: RecordType.catalog)
        return records.compactMap(Self.catalog(from:)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func fetchInstances() async throws -> [PlantInstanceDetail] {
        try await requireiCloud()
        let catalogByID = Dictionary(uniqueKeysWithValues: try await fetchCatalog().map { ($0.id, $0) })
        let records = try await ownedRecords(ofType: RecordType.instance)
        return records.compactMap { record in
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
        let instanceRecordID = CKRecord.ID(recordName: instanceID.uuidString)
        let instanceRecord: CKRecord
        do {
            instanceRecord = try await database.record(for: instanceRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }

        guard let instance = Self.instance(from: instanceRecord, photoData: photoData(from: instanceRecord))
        else { return nil }

        let catalogRecord = try await database.record(
            for: CKRecord.ID(recordName: instance.catalogItemID.uuidString)
        )
        guard let catalog = Self.catalog(from: catalogRecord) else { return nil }

        let historyRecords = try await ownedRecords(ofType: RecordType.careEvent)
        let history = historyRecords.compactMap(Self.careEvent(from:)).filter { $0.instanceID == instanceID }

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

        var details: [PlantInstanceDetail] = []
        details.reserveCapacity(draft.quantity)

        for _ in 0..<draft.quantity {
            let instanceID = UUID()
            let record = CKRecord(recordType: RecordType.instance, recordID: CKRecord.ID(recordName: instanceID.uuidString))
            record["id"] = instanceID.uuidString
            record["catalogItemID"] = catalog.id.uuidString
            record["arrivedOn"] = arrivedOn
            record["vendor"] = vendor
            record["createdAt"] = Date()

            if let photoData = draft.photoData {
                record["photo"] = try Self.asset(from: photoData, name: instanceID.uuidString)
                photoCache[instanceID] = photoData
            }

            _ = try await database.save(record)
            try await verifySaved(
                record.recordID,
                type: RecordType.instance,
                keys: ["catalogItemID", "vendor", "arrivedOn"]
            )

            let instance = PlantInstance(
                id: instanceID,
                catalogItemID: catalog.id,
                arrivedOn: arrivedOn,
                vendor: vendor,
                photoData: draft.photoData,
                createdAt: Date()
            )
            details.append(PlantInstanceDetail(instance: instance, catalog: catalog))
        }

        return PlantArrivalBatch(catalog: catalog, instances: details)
    }

    func addCareEvent(_ event: CareEvent) async throws {
        try await requireiCloud()
        let instanceID = CKRecord.ID(recordName: event.instanceID.uuidString)
        do {
            _ = try await database.record(for: instanceID)
        } catch {
            throw RepositoryError.instanceNotFound
        }

        let record = CKRecord(recordType: RecordType.careEvent, recordID: CKRecord.ID(recordName: event.id.uuidString))
        record["id"] = event.id.uuidString
        record["instanceID"] = event.instanceID.uuidString
        record["kind"] = event.kind.rawValue
        record["performedAt"] = event.performedAt
        record["wateringObservation"] = event.wateringObservation
        record["healthObservation"] = event.healthObservation
        record["notes"] = event.notes
        _ = try await database.save(record)
        try await verifySaved(
            record.recordID,
            type: RecordType.careEvent,
            keys: ["instanceID", "kind", "performedAt"]
        )
    }

    func updateCareProfile(catalogItemID: UUID, profile: PlantCareProfile) async throws {
        try await requireiCloud()
        let recordID = CKRecord.ID(recordName: catalogItemID.uuidString)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch {
            throw RepositoryError.catalogNotFound
        }
        record["careInstructions"] = profile.careInstructions
        record["wateringCheckGuidance"] = profile.wateringCheckGuidance
        record["healthCheckGuidance"] = profile.healthCheckGuidance
        _ = try await database.save(record)
    }

    func referencePhoto(for catalogItemID: UUID) async throws -> Data? {
        try await requireiCloud()
        let records = try await ownedRecords(ofType: RecordType.instance)
            .filter { ($0["catalogItemID"] as? String) == catalogItemID.uuidString }
            .sorted { lhs, rhs in
                let left = lhs["createdAt"] as? Date ?? .distantPast
                let right = rhs["createdAt"] as? Date ?? .distantPast
                return left > right
            }
        for record in records.prefix(12) {
            if let data = photoData(from: record) {
                return data
            }
        }
        return nil
    }

    // MARK: - Account

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    func userRecordName() async throws -> String {
        try await container.userRecordID().recordName
    }

    // MARK: - Private

    private enum RecordType {
        static let catalog = "CatalogItem"
        static let instance = "PlantInstance"
        static let careEvent = "CareEvent"
    }

    private static let ownedTypes: Set<String> = [
        RecordType.catalog,
        RecordType.instance,
        RecordType.careEvent,
    ]

    private func requireiCloud() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw RepositoryError.notSignedIn
        }
    }

    private func resolveCatalog(for draft: PlantIntakeDraft) async throws -> PlantCatalogItem {
        switch draft.catalogMode {
        case .existingType(let catalogItemID):
            let record = try await database.record(for: CKRecord.ID(recordName: catalogItemID.uuidString))
            guard let item = Self.catalog(from: record) else { throw RepositoryError.catalogNotFound }
            return item

        case .newOrMatchType:
            let existing = try await fetchCatalog()
            if let match = PlantCatalogMatcher.findExisting(
                name: draft.name,
                genus: draft.genus,
                in: existing
            ) {
                return match
            }

            let item = PlantCatalogItem(
                name: draft.name,
                genus: draft.genus,
                careProfile: draft.careProfile
            )
            let recordID = CKRecord.ID(recordName: item.id.uuidString)
            let record = CKRecord(recordType: RecordType.catalog, recordID: recordID)
            Self.apply(item, to: record)
            _ = try await database.save(record)
            try await verifySaved(
                recordID,
                type: RecordType.catalog,
                keys: ["name", "genus", "createdAt"]
            )
            return item
        }
    }

    /// All Gardens records in the public default zone.
    /// Zone changes do not require `recordName` (or any field) to be queryable.
    /// Apple's `Users` type is skipped — it has no app fields.
    private func ownedRecords(ofType type: String) async throws -> [CKRecord] {
        try await fetchOwnedRecords().filter { $0.recordType == type }
    }

    private func fetchOwnedRecords() async throws -> [CKRecord] {
        let zoneID = CKRecordZone.default().zoneID
        var token: CKServerChangeToken?
        var byID: [CKRecord.ID: CKRecord] = [:]

        for _ in 0..<30 {
            let page = try await fetchZonePage(zoneID: zoneID, since: token)
            for record in page.records where Self.ownedTypes.contains(record.recordType) {
                byID[record.recordID] = record
            }
            token = page.changeToken
            if !page.moreComing { break }
        }
        return Array(byID.values)
    }

    private struct ZonePage {
        var records: [CKRecord]
        var changeToken: CKServerChangeToken?
        var moreComing: Bool
    }

    private func fetchZonePage(
        zoneID: CKRecordZone.ID,
        since token: CKServerChangeToken?
    ) async throws -> ZonePage {
        try await withCheckedThrowingContinuation { continuation in
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = token
            // The no-argument initializer leaves zone IDs empty and CloudKit rejects the op.
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )

            let box = CloudKitRecordBox()
            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result {
                    box.append(record)
                }
            }

            var pageToken: CKServerChangeToken?
            var moreComing = false
            var zoneError: Error?

            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .failure(let error):
                    zoneError = error
                case .success(let info):
                    pageToken = info.serverChangeToken
                    moreComing = info.moreComing
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .failure(let error):
                    if Self.isBenignEmpty(error) {
                        continuation.resume(returning: ZonePage(records: [], changeToken: nil, moreComing: false))
                    } else {
                        continuation.resume(throwing: error)
                    }
                case .success:
                    if let zoneError, !Self.isBenignEmpty(zoneError) {
                        continuation.resume(throwing: zoneError)
                    } else {
                        continuation.resume(
                            returning: ZonePage(
                                records: box.all(),
                                changeToken: pageToken,
                                moreComing: moreComing
                            )
                        )
                    }
                }
            }

            database.add(operation)
        }
    }

    private func verifySaved(_ id: CKRecord.ID, type: String, keys: [String]) async throws {
        let record = try await database.record(for: id)
        guard record.recordType == type else { throw RepositoryError.saveFailed }
        for key in keys where record[key] == nil {
            throw RepositoryError.saveFailed
        }
    }

    /// Empty schema / first launch. `Users` is Apple's account type and is ignored.
    private static func isBenignEmpty(_ error: Error) -> Bool {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("Did not find record type") {
            return true
        }
        guard let ck = error as? CKError else { return false }
        if let partial = ck.partialErrorsByItemID {
            for (_, nested) in partial {
                if isBenignEmpty(nested) { return true }
            }
        }
        // Some SDKs surface this under unknownItem / invalidArguments / serverRejectedRequest.
        switch ck.code {
        case .unknownItem, .invalidArguments, .serverRejectedRequest:
            return text.localizedCaseInsensitiveContains("record type")
        default:
            return false
        }
    }

    private func photoData(from record: CKRecord) -> Data? {
        if let idString = record["id"] as? String, let id = UUID(uuidString: idString),
           let cached = photoCache[id] {
            return cached
        }
        guard let asset = record["photo"] as? CKAsset,
              let url = asset.fileURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
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
