import Foundation
import SwiftData
import GardensCore

@MainActor
final class SwiftDataPlantRepository: PlantRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchCatalog() async throws -> [PlantCatalogItem] {
        let descriptor = FetchDescriptor<CatalogItemEntity>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func fetchInstances() async throws -> [PlantInstanceDetail] {
        let descriptor = FetchDescriptor<PlantInstanceEntity>(
            sortBy: [SortDescriptor(\.arrivedOn, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap { $0.toDetail() }
    }

    func destination(for instanceID: UUID) async throws -> PlantInstanceDestination? {
        let descriptor = FetchDescriptor<PlantInstanceEntity>(
            predicate: #Predicate { $0.id == instanceID }
        )
        guard let entity = try modelContext.fetch(descriptor).first,
              let catalog = entity.catalog,
              let instance = entity.toDomain() else { return nil }

        let history = entity.careEvents.compactMap { $0.toDomain() }
        let catalogItem = catalog.toDomain()
        return PlantInstanceDestination(
            instance: instance,
            catalog: catalogItem,
            careProfile: catalogItem.careProfile,
            careHistory: history
        )
    }

    func saveIntake(_ draft: PlantIntakeDraft) async throws -> PlantInstanceDetail {
        let catalog = try resolveOrCreateCatalog(for: draft)
        let instance = PlantInstanceEntity(
            catalog: catalog,
            arrivedOn: Calendar.current.startOfDay(for: draft.arrivedOn),
            vendor: draft.vendor.trimmingCharacters(in: .whitespacesAndNewlines),
            photoData: draft.photoData
        )
        modelContext.insert(instance)
        try modelContext.save()
        guard let detail = instance.toDetail() else {
            throw RepositoryError.saveFailed
        }
        return detail
    }

    func addCareEvent(_ event: CareEvent) async throws {
        let descriptor = FetchDescriptor<PlantInstanceEntity>(
            predicate: #Predicate { $0.id == event.instanceID }
        )
        guard let instance = try modelContext.fetch(descriptor).first else {
            throw RepositoryError.instanceNotFound
        }
        let entity = CareEventEntity(from: event, instance: instance)
        modelContext.insert(entity)
        try modelContext.save()
    }

    func updateCareProfile(catalogItemID: UUID, profile: PlantCareProfile) async throws {
        let descriptor = FetchDescriptor<CatalogItemEntity>(
            predicate: #Predicate { $0.id == catalogItemID }
        )
        guard let catalog = try modelContext.fetch(descriptor).first else {
            throw RepositoryError.catalogNotFound
        }
        catalog.applyCareProfile(profile)
        try modelContext.save()
    }

    // MARK: - Catalog reuse

    private func resolveOrCreateCatalog(for draft: PlantIntakeDraft) throws -> CatalogItemEntity {
        let existing = try modelContext.fetch(FetchDescriptor<CatalogItemEntity>())
        let domain = existing.map { $0.toDomain() }
        if let match = PlantCatalogMatcher.findExisting(
            name: draft.name,
            genus: draft.genus,
            in: domain
        ),
           let entity = existing.first(where: { $0.id == match.id }) {
            return entity
        }

        let item = PlantCatalogItem(
            name: draft.name,
            genus: draft.genus,
            careProfile: draft.careProfile
        )
        let entity = CatalogItemEntity(from: item)
        modelContext.insert(entity)
        return entity
    }
}

enum RepositoryError: Error {
    case saveFailed
    case instanceNotFound
    case catalogNotFound
}
