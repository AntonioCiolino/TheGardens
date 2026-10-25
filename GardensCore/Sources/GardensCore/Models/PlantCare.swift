import Foundation

/// Species-level care guidance attached to a catalog item.
public struct PlantCareProfile: Hashable, Codable, Sendable {
    public var careInstructions: String
    public var wateringCheckGuidance: String
    public var healthCheckGuidance: String

    public init(
        careInstructions: String = "",
        wateringCheckGuidance: String = "",
        healthCheckGuidance: String = ""
    ) {
        self.careInstructions = careInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        self.wateringCheckGuidance = wateringCheckGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
        self.healthCheckGuidance = healthCheckGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static let empty = PlantCareProfile()
}

public enum CareEventKind: String, Codable, Sendable, CaseIterable, Hashable {
    case watered
    case fertilized
    case pruned
    case repotted
    case healthCheck
    case note
    case other
}

/// Care action recorded against one physical plant instance.
public struct CareEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var instanceID: UUID
    public var kind: CareEventKind
    public var performedAt: Date
    public var notes: String

    public init(
        id: UUID = UUID(),
        instanceID: UUID,
        kind: CareEventKind,
        performedAt: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.instanceID = instanceID
        self.kind = kind
        self.performedAt = performedAt
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Full destination loaded by instance ID after a QR scan.
public struct PlantInstanceDestination: Identifiable, Hashable, Codable, Sendable {
    public var instance: PlantInstance
    public var catalog: PlantCatalogItem
    public var careProfile: PlantCareProfile
    public var careHistory: [CareEvent]

    public var id: UUID { instance.id }

    public init(
        instance: PlantInstance,
        catalog: PlantCatalogItem,
        careProfile: PlantCareProfile,
        careHistory: [CareEvent]
    ) {
        self.instance = instance
        self.catalog = catalog
        self.careProfile = careProfile
        self.careHistory = careHistory.sorted { $0.performedAt > $1.performedAt }
    }
}
