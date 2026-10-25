import Foundation

/// A plant *type* in the catalog (species / cultivar identity).
/// Pure Swift — safe to share with future Android/web ports.
///
/// Multiple physical plants of the same type reuse one catalog record.
public struct PlantCatalogItem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var genus: String
    /// Simple color / foliage descriptor (also embedded in compact QR).
    public var color: String
    public var careProfile: PlantCareProfile
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        genus: String,
        color: String = "",
        careProfile: PlantCareProfile = .empty,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.genus = genus.trimmingCharacters(in: .whitespacesAndNewlines)
        self.color = color.trimmingCharacters(in: .whitespacesAndNewlines)
        self.careProfile = careProfile
        self.createdAt = createdAt
    }

    public var matchKey: String {
        PlantCatalogMatcher.matchKey(name: name, genus: genus)
    }
}
