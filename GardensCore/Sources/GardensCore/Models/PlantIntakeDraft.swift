import Foundation

/// Form state for adding a plant. Maps to catalog match + new instance on save.
public struct PlantIntakeDraft: Hashable, Sendable {
    public var name: String
    public var genus: String
    public var color: String
    public var vendor: String
    public var arrivedOn: Date
    public var photoData: Data?
    public var careProfile: PlantCareProfile

    public init(
        name: String = "",
        genus: String = "",
        color: String = "",
        vendor: String = "",
        arrivedOn: Date = Date(),
        photoData: Data? = nil,
        careProfile: PlantCareProfile = .empty
    ) {
        self.name = name
        self.genus = genus
        self.color = color
        self.vendor = vendor
        self.arrivedOn = arrivedOn
        self.photoData = photoData
        self.careProfile = careProfile
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !genus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
