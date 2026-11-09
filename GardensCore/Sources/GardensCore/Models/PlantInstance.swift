import Foundation

/// One physical plant that arrived in inventory.
/// Even if three plants are the same species, that is three instances —
/// each with its own photo, arrival date, vendor, and catalog reference.
public struct PlantInstance: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var catalogItemID: UUID
    public var arrivedOn: Date
    public var vendor: String
    /// JPEG (or other) image bytes; platform layers choose encoding.
    public var photoData: Data?
    /// Set when the photo is a reference image rather than a picture of this plant.
    public var photoCredit: String?
    public var createdAt: Date
    /// Display name of the team member who logged this arrival. Empty when unknown (older records).
    public var createdByName: String
    /// Stable CloudKit user record name of the team member who logged this arrival.
    public var createdByRecordName: String?

    public init(
        id: UUID = UUID(),
        catalogItemID: UUID,
        arrivedOn: Date = Date(),
        vendor: String,
        photoData: Data? = nil,
        photoCredit: String? = nil,
        createdAt: Date = Date(),
        createdByName: String = "",
        createdByRecordName: String? = nil
    ) {
        self.id = id
        self.catalogItemID = catalogItemID
        self.arrivedOn = Calendar.current.startOfDay(for: arrivedOn)
        self.vendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        self.photoData = photoData
        self.photoCredit = photoCredit
        self.createdAt = createdAt
        self.createdByName = createdByName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdByRecordName = createdByRecordName
    }
}

/// Instance plus its resolved catalog row for list/detail UI.
public struct PlantInstanceDetail: Identifiable, Hashable, Codable, Sendable {
    public var instance: PlantInstance
    public var catalog: PlantCatalogItem
    /// When this plant was last cared for (latest care event), if any. Used to surface
    /// the plants most overdue for attention. `nil` means no care has been logged yet.
    public var lastCaredAt: Date?

    public var id: UUID { instance.id }

    public init(instance: PlantInstance, catalog: PlantCatalogItem, lastCaredAt: Date? = nil) {
        self.instance = instance
        self.catalog = catalog
        self.lastCaredAt = lastCaredAt
    }

    /// The date used to rank attention: the last care date, or arrival date if never cared for.
    public var attentionDate: Date {
        lastCaredAt ?? instance.arrivedOn
    }
}
