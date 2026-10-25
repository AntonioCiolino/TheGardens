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

    public var displayName: String {
        switch self {
        case .watered: return "Watered"
        case .fertilized: return "Fertilized"
        case .pruned: return "Pruned"
        case .repotted: return "Repotted"
        case .healthCheck: return "Health check"
        case .note: return "Note"
        case .other: return "Other maintenance"
        }
    }
}

/// Care / health update recorded against one physical plant instance.
public struct CareEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var instanceID: UUID
    public var kind: CareEventKind
    public var performedAt: Date
    /// What you observed when checking watering (soil dry, already moist, …).
    public var wateringObservation: String
    /// What you observed about plant health (pests, leaf color, …).
    public var healthObservation: String
    /// Extra free-form notes about the maintenance just performed.
    public var notes: String

    public init(
        id: UUID = UUID(),
        instanceID: UUID,
        kind: CareEventKind,
        performedAt: Date = Date(),
        wateringObservation: String = "",
        healthObservation: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.instanceID = instanceID
        self.kind = kind
        self.performedAt = performedAt
        self.wateringObservation = wateringObservation.trimmingCharacters(in: .whitespacesAndNewlines)
        self.healthObservation = healthObservation.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var hasContent: Bool {
        kind != .note
            || !wateringObservation.isEmpty
            || !healthObservation.isEmpty
            || !notes.isEmpty
    }
}

/// Form draft for logging maintenance after scanning a plant.
public struct CareUpdateDraft: Hashable, Sendable {
    public var instanceID: UUID
    public var kind: CareEventKind
    public var performedAt: Date
    public var wateringObservation: String
    public var healthObservation: String
    public var notes: String

    public init(
        instanceID: UUID,
        kind: CareEventKind = .healthCheck,
        performedAt: Date = Date(),
        wateringObservation: String = "",
        healthObservation: String = "",
        notes: String = ""
    ) {
        self.instanceID = instanceID
        self.kind = kind
        self.performedAt = performedAt
        self.wateringObservation = wateringObservation
        self.healthObservation = healthObservation
        self.notes = notes
    }

    public var isValid: Bool {
        !wateringObservation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !healthObservation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || kind != .note
    }

    public func makeEvent() -> CareEvent {
        CareEvent(
            instanceID: instanceID,
            kind: kind,
            performedAt: performedAt,
            wateringObservation: wateringObservation,
            healthObservation: healthObservation,
            notes: notes
        )
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
