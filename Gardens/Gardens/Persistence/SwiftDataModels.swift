import Foundation
import SwiftData
import GardensCore

@Model
final class CatalogItemEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var genus: String
    var careInstructions: String
    var wateringCheckGuidance: String
    var healthCheckGuidance: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlantInstanceEntity.catalog)
    var instances: [PlantInstanceEntity]

    init(from item: PlantCatalogItem) {
        self.id = item.id
        self.name = item.name
        self.genus = item.genus
        self.careInstructions = item.careProfile.careInstructions
        self.wateringCheckGuidance = item.careProfile.wateringCheckGuidance
        self.healthCheckGuidance = item.careProfile.healthCheckGuidance
        self.createdAt = item.createdAt
        self.instances = []
    }

    func toDomain() -> PlantCatalogItem {
        PlantCatalogItem(
            id: id,
            name: name,
            genus: genus,
            careProfile: PlantCareProfile(
                careInstructions: careInstructions,
                wateringCheckGuidance: wateringCheckGuidance,
                healthCheckGuidance: healthCheckGuidance
            ),
            createdAt: createdAt
        )
    }

    func applyCareProfile(_ profile: PlantCareProfile) {
        careInstructions = profile.careInstructions
        wateringCheckGuidance = profile.wateringCheckGuidance
        healthCheckGuidance = profile.healthCheckGuidance
    }
}

@Model
final class PlantInstanceEntity {
    @Attribute(.unique) var id: UUID
    var arrivedOn: Date
    var vendor: String
    @Attribute(.externalStorage) var photoData: Data?
    var photoCredit: String?
    var createdAt: Date
    var createdByName: String = ""
    var createdByRecordName: String?
    var catalog: CatalogItemEntity?

    @Relationship(deleteRule: .cascade, inverse: \CareEventEntity.instance)
    var careEvents: [CareEventEntity]

    init(
        id: UUID = UUID(),
        catalog: CatalogItemEntity,
        arrivedOn: Date,
        vendor: String,
        photoData: Data?,
        photoCredit: String? = nil,
        createdAt: Date = Date(),
        createdByName: String = "",
        createdByRecordName: String? = nil
    ) {
        self.id = id
        self.catalog = catalog
        self.arrivedOn = arrivedOn
        self.vendor = vendor
        self.photoData = photoData
        self.photoCredit = photoCredit
        self.createdAt = createdAt
        self.createdByName = createdByName
        self.createdByRecordName = createdByRecordName
        self.careEvents = []
    }

    func toDomain() -> PlantInstance? {
        guard let catalog else { return nil }
        return PlantInstance(
            id: id,
            catalogItemID: catalog.id,
            arrivedOn: arrivedOn,
            vendor: vendor,
            photoData: photoData,
            photoCredit: photoCredit,
            createdAt: createdAt,
            createdByName: createdByName,
            createdByRecordName: createdByRecordName
        )
    }

    func toDetail() -> PlantInstanceDetail? {
        guard let catalog, let instance = toDomain() else { return nil }
        let lastCaredAt = careEvents.map(\.performedAt).max()
        return PlantInstanceDetail(instance: instance, catalog: catalog.toDomain(), lastCaredAt: lastCaredAt)
    }
}

@Model
final class CareEventEntity {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var performedAt: Date
    var wateringObservation: String
    var healthObservation: String
    var notes: String
    var performedByName: String = ""
    var performedByRecordName: String?
    var instance: PlantInstanceEntity?

    init(from event: CareEvent, instance: PlantInstanceEntity) {
        self.id = event.id
        self.kindRaw = event.kind.rawValue
        self.performedAt = event.performedAt
        self.wateringObservation = event.wateringObservation
        self.healthObservation = event.healthObservation
        self.notes = event.notes
        self.performedByName = event.performedByName
        self.performedByRecordName = event.performedByRecordName
        self.instance = instance
    }

    func toDomain() -> CareEvent? {
        guard let instance, let kind = CareEventKind(rawValue: kindRaw) else { return nil }
        return CareEvent(
            id: id,
            instanceID: instance.id,
            kind: kind,
            performedAt: performedAt,
            wateringObservation: wateringObservation,
            healthObservation: healthObservation,
            notes: notes,
            performedByName: performedByName,
            performedByRecordName: performedByRecordName
        )
    }
}
