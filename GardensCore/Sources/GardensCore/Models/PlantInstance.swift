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
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        catalogItemID: UUID,
        arrivedOn: Date = Date(),
        vendor: String,
        photoData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.catalogItemID = catalogItemID
        self.arrivedOn = Calendar.current.startOfDay(for: arrivedOn)
        self.vendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        self.photoData = photoData
        self.createdAt = createdAt
    }
}

/// Instance plus its resolved catalog row for list/detail UI.
public struct PlantInstanceDetail: Identifiable, Hashable, Codable, Sendable {
    public var instance: PlantInstance
    public var catalog: PlantCatalogItem

    public var id: UUID { instance.id }

    public init(instance: PlantInstance, catalog: PlantCatalogItem) {
        self.instance = instance
        self.catalog = catalog
    }
}
