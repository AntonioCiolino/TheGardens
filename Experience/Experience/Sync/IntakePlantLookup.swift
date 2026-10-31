import Foundation
import CloudKit
import GardensCore

/// Read-only lookup of one plant in the Intake public database.
/// Record IDs match `CloudKitPlantRepository`: the instance UUID in the default zone.
/// This type never saves or deletes.
@MainActor
final class IntakePlantLookup {
    nonisolated static let containerID = "iCloud.com.gardens.intake"

    private let database: CKDatabase

    init(container: CKContainer? = nil) {
        let resolved = container ?? CKContainer(identifier: Self.containerID)
        self.database = resolved.publicCloudDatabase
    }

    /// Instance record, then its catalog record. Care history is not loaded.
    func destination(for instanceID: UUID) async throws -> PlantInstanceDestination? {
        let instanceRecord: CKRecord
        do {
            instanceRecord = try await cloudRecord(for: Self.recordID(instanceID.uuidString))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        guard let instance = Self.instance(from: instanceRecord) else { return nil }

        let catalogRecord: CKRecord
        do {
            catalogRecord = try await cloudRecord(for: Self.recordID(instance.catalogItemID.uuidString))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        guard let catalog = Self.catalog(from: catalogRecord) else { return nil }

        return PlantInstanceDestination(
            instance: instance,
            catalog: catalog,
            careProfile: catalog.careProfile,
            careHistory: []
        )
    }

    private func cloudRecord(for id: CKRecord.ID) async throws -> CKRecord {
        try await within(.seconds(12)) { try await self.database.record(for: id) }
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
                    continuation.resume(throwing: IntakeLookupTimeout())
                }
            }
        }
    }

    private static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: CKRecordZone.default().zoneID)
    }

    private static func catalog(from record: CKRecord) -> PlantCatalogItem? {
        let idString = (record["id"] as? String) ?? record.recordID.recordName
        guard let id = UUID(uuidString: idString) else { return nil }
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

    private static func instance(from record: CKRecord) -> PlantInstance? {
        let idString = (record["id"] as? String) ?? record.recordID.recordName
        guard
            let id = UUID(uuidString: idString),
            let catalogString = record["catalogItemID"] as? String,
            let catalogID = UUID(uuidString: catalogString)
        else { return nil }
        return PlantInstance(
            id: id,
            catalogItemID: catalogID,
            arrivedOn: record["arrivedOn"] as? Date ?? Date(),
            vendor: record["vendor"] as? String ?? "",
            photoData: photoData(from: record),
            photoCredit: record["photoCredit"] as? String,
            createdAt: record["createdAt"] as? Date ?? Date()
        )
    }

    private static func photoData(from record: CKRecord) -> Data? {
        guard let asset = record["photo"] as? CKAsset, let url = asset.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }
}

private struct IntakeLookupTimeout: LocalizedError {
    var errorDescription: String? {
        "iCloud didn’t answer. A plant you’ve opened before can still show from this iPhone."
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
