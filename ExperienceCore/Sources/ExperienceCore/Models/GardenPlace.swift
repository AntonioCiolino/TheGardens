import Foundation

/// One place the phone can watch. A missing coordinate means the place is not monitored.
public struct GardenPlace: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var latitude: Double?
    public var longitude: Double?
    public var radiusMeters: Double
    public var enabled: Bool
    public var note: String?

    public init(
        id: UUID,
        name: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusMeters: Double,
        enabled: Bool,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.enabled = enabled
        self.note = note
    }

    /// Enabled, with a real center, and a radius iOS region monitoring can honor.
    public var isMonitorable: Bool {
        guard enabled, let latitude, let longitude else { return false }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        guard latitude != 0 || longitude != 0 else { return false }
        return radiusMeters >= GardenPlaceCatalog.minimumRadiusMeters
    }
}
