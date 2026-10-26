import Foundation

/// Persistence boundary for catalog + instances + care history.
/// iOS uses SwiftData; Android/web can swap implementations later.
public protocol PlantRepository: AnyObject {
    func fetchCatalog() async throws -> [PlantCatalogItem]
    func fetchInstances() async throws -> [PlantInstanceDetail]
    func destination(for instanceID: UUID) async throws -> PlantInstanceDestination?
    /// Saves an arrival of `draft.quantity` unique instances (shared catalog type).
    func saveIntake(_ draft: PlantIntakeDraft) async throws -> PlantArrivalBatch
    func addCareEvent(_ event: CareEvent) async throws
    func updateCareProfile(catalogItemID: UUID, profile: PlantCareProfile) async throws
    /// Replaces or clears the photo on one physical plant.
    /// `photoCredit` is kept when the image is a reference photo, and cleared for a picture of the plant.
    func updateInstancePhoto(instanceID: UUID, photoData: Data?, photoCredit: String?) async throws
    /// Deletes one physical plant and its care notes.
    /// When no plants of that type remain, the type is removed so it no longer appears as an existing plant.
    func deleteInstance(instanceID: UUID) async throws
    /// Most recent photo already stored for this catalog type (for restock intake).
    func referencePhoto(for catalogItemID: UUID) async throws -> Data?
}

/// Application service: intake matching + QR destination assembly.
public struct PlantIntakeService {
    private let repository: any PlantRepository

    public init(repository: any PlantRepository) {
        self.repository = repository
    }

    /// First-time or repeat arrival — creates `quantity` unique instances + QRs.
    @discardableResult
    public func saveNewArrival(_ draft: PlantIntakeDraft) async throws -> PlantArrivalBatch {
        try await repository.saveIntake(draft)
    }

    /// Decode compact QR → load full destination from the store by instance ID.
    public func destination(fromScannedQR string: String) async throws -> PlantInstanceDestination {
        guard let id = CompactPlantQR.instanceID(fromScanned: string) else {
            throw PlantQRError.invalidCode
        }
        guard let destination = try await repository.destination(for: id) else {
            throw PlantQRError.unknownInstance
        }
        return destination
    }

    public func compactQR(for detail: PlantInstanceDetail) throws -> String {
        try CompactPlantQR(detail: detail).encodedString()
    }

    public func compactQRs(for batch: PlantArrivalBatch) throws -> [(PlantInstanceDetail, String)] {
        try batch.instances.map { detail in
            (detail, try compactQR(for: detail))
        }
    }

    /// Persist a maintenance / health update against a scanned instance.
    @discardableResult
    public func logCareUpdate(_ draft: CareUpdateDraft) async throws -> CareEvent {
        let event = draft.makeEvent()
        try await repository.addCareEvent(event)
        return event
    }
}
