import Foundation

/// Persistence boundary for catalog + instances + care history.
/// iOS uses SwiftData; Android/web can swap implementations later.
public protocol PlantRepository: AnyObject {
    func fetchCatalog() async throws -> [PlantCatalogItem]
    func fetchInstances() async throws -> [PlantInstanceDetail]
    func destination(for instanceID: UUID) async throws -> PlantInstanceDestination?
    func saveIntake(_ draft: PlantIntakeDraft) async throws -> PlantInstanceDetail
    func addCareEvent(_ event: CareEvent) async throws
    func updateCareProfile(catalogItemID: UUID, profile: PlantCareProfile) async throws
}

/// Application service: intake matching + QR destination assembly.
public struct PlantIntakeService {
    private let repository: any PlantRepository

    public init(repository: any PlantRepository) {
        self.repository = repository
    }

    @discardableResult
    public func saveNewArrival(_ draft: PlantIntakeDraft) async throws -> PlantInstanceDetail {
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
}
