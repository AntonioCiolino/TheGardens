import Foundation
import SwiftData
import GardensCore

/// Last plants a guest opened. Used when the intake database can’t be reached.
@Model
final class ViewedPlantEntity {
    @Attribute(.unique) var id: UUID
    var catalogItemID: UUID
    var name: String
    var careInstructions: String
    var wateringCheckGuidance: String
    var healthCheckGuidance: String
    @Attribute(.externalStorage) var photoData: Data?
    var viewedAt: Date

    init(from destination: PlantInstanceDestination, viewedAt: Date = Date()) {
        id = destination.instance.id
        catalogItemID = destination.catalog.id
        name = destination.catalog.name
        careInstructions = destination.careProfile.careInstructions
        wateringCheckGuidance = destination.careProfile.wateringCheckGuidance
        healthCheckGuidance = destination.careProfile.healthCheckGuidance
        photoData = destination.instance.photoData
        self.viewedAt = viewedAt
    }

    func apply(_ destination: PlantInstanceDestination) {
        catalogItemID = destination.catalog.id
        name = destination.catalog.name
        careInstructions = destination.careProfile.careInstructions
        wateringCheckGuidance = destination.careProfile.wateringCheckGuidance
        healthCheckGuidance = destination.careProfile.healthCheckGuidance
        photoData = destination.instance.photoData
        viewedAt = Date()
    }

    func toDestination() -> PlantInstanceDestination {
        let profile = PlantCareProfile(
            careInstructions: careInstructions,
            wateringCheckGuidance: wateringCheckGuidance,
            healthCheckGuidance: healthCheckGuidance
        )
        let catalog = PlantCatalogItem(
            id: catalogItemID,
            name: name,
            genus: "",
            careProfile: profile,
            createdAt: viewedAt
        )
        let instance = PlantInstance(
            id: id,
            catalogItemID: catalogItemID,
            arrivedOn: viewedAt,
            vendor: "",
            photoData: photoData,
            createdAt: viewedAt
        )
        return PlantInstanceDestination(
            instance: instance,
            catalog: catalog,
            careProfile: profile,
            careHistory: []
        )
    }
}

@MainActor
final class ViewedPlantCache {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save(_ destination: PlantInstanceDestination) throws {
        let id = destination.instance.id
        let descriptor = FetchDescriptor<ViewedPlantEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(destination)
        } else {
            modelContext.insert(ViewedPlantEntity(from: destination))
        }
        try modelContext.save()
    }

    func destination(for instanceID: UUID) throws -> PlantInstanceDestination? {
        let descriptor = FetchDescriptor<ViewedPlantEntity>(
            predicate: #Predicate { $0.id == instanceID }
        )
        return try modelContext.fetch(descriptor).first?.toDestination()
    }
}
