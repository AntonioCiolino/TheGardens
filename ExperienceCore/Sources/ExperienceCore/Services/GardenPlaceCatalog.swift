import Foundation

/// Which places become `CLCircularRegion`s. iOS allows 20 monitored regions.
/// The catalog does not poll GPS; the app registers one circle per place.
public enum GardenPlaceCatalog {
    public static let maximumMonitoredRegions = 20
    public static let minimumRadiusMeters = 100.0

    public static func load(from data: Data) throws -> [GardenPlace] {
        try JSONDecoder().decode([GardenPlace].self, from: data)
    }

    /// Enabled places that have their own coordinates, in file order, capped at 20.
    public static func placesToMonitor(_ places: [GardenPlace]) -> [GardenPlace] {
        Array(places.filter(\.isMonitorable).prefix(maximumMonitoredRegions))
    }
}
