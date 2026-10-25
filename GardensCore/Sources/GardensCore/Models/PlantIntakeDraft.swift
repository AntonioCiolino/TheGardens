import Foundation

/// How an arrival maps onto the catalog.
public enum IntakeCatalogMode: Hashable, Sendable {
    /// Create a catalog row if needed (or match by name+genus), then mint instances.
    case newOrMatchType
    /// Always attach to an existing catalog plant type.
    case existingType(catalogItemID: UUID)
}

/// Form state for an arrival shipment of one plant type.
/// `quantity` creates that many unique instances (each with its own QR).
public struct PlantIntakeDraft: Hashable, Sendable {
    public var catalogMode: IntakeCatalogMode
    public var name: String
    public var genus: String
    public var vendor: String
    public var arrivedOn: Date
    public var photoData: Data?
    public var careProfile: PlantCareProfile
    /// Number of physical plants in this arrival (each becomes its own instance + QR).
    public var quantity: Int

    public init(
        catalogMode: IntakeCatalogMode = .newOrMatchType,
        name: String = "",
        genus: String = "",
        vendor: String = "",
        arrivedOn: Date = Date(),
        photoData: Data? = nil,
        careProfile: PlantCareProfile = .empty,
        quantity: Int = 1
    ) {
        self.catalogMode = catalogMode
        self.name = name
        self.genus = genus
        self.vendor = vendor
        self.arrivedOn = arrivedOn
        self.photoData = photoData
        self.careProfile = careProfile
        self.quantity = max(1, quantity)
    }

    public var isValid: Bool {
        guard quantity >= 1 else { return false }
        let vendorOK = !vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch catalogMode {
        case .existingType:
            return vendorOK
        case .newOrMatchType:
            return vendorOK
                && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !genus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// Result of saving an arrival: one catalog type, many unique instances.
public struct PlantArrivalBatch: Identifiable, Hashable, Sendable {
    public var catalog: PlantCatalogItem
    public var instances: [PlantInstanceDetail]

    public var id: UUID { instances.first?.id ?? catalog.id }
    public var count: Int { instances.count }

    public init(catalog: PlantCatalogItem, instances: [PlantInstanceDetail]) {
        self.catalog = catalog
        self.instances = instances
    }
}
