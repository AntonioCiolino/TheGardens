import Foundation
import CoreLocation
import ExperienceCore

/// Watches one circular region per enabled place. Does not call `startUpdatingLocation`.
@MainActor
final class GardenGeofenceMonitor: NSObject, ObservableObject {
    @Published private(set) var welcomePlace: GardenPlace?
    @Published private(set) var authorization = CLAuthorizationStatus.notDetermined
    @Published private(set) var statusMessage: String?

    private let manager = CLLocationManager()
    private var places: [GardenPlace] = []
    private let arrivalCooldown: TimeInterval = 60 * 60

    func start() {
        places = GardenPlaceLoader.load()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            registerRegions()
        case .authorizedAlways:
            registerRegions()
        case .denied, .restricted:
            statusMessage = "Location is off. The welcome appears when you allow it."
        @unknown default:
            break
        }
        authorization = manager.authorizationStatus
    }

    func dismissWelcome() {
        welcomePlace = nil
    }

    func previewWelcome() {
        welcomePlace = places.first(where: \.enabled) ?? places.first ?? GardenPlace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            name: "The Gardens",
            radiusMeters: GardenPlaceCatalog.minimumRadiusMeters,
            enabled: false
        )
    }

    private func registerRegions() {
        let wanted = GardenPlaceCatalog.placesToMonitor(places)
        let wantedIDs = Set(wanted.map { $0.id.uuidString })
        for region in manager.monitoredRegions where !wantedIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        for place in wanted {
            guard let latitude = place.latitude, let longitude = place.longitude else { continue }
            let limit = manager.maximumRegionMonitoringDistance
            let radius = limit > 0 ? min(place.radiusMeters, limit) : place.radiusMeters
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                radius: radius,
                identifier: place.id.uuidString
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
            manager.requestState(for: region)
        }
        if wanted.isEmpty {
            statusMessage = "No garden locations are turned on yet."
        } else {
            let names = wanted.map(\.name).joined(separator: ", ")
            statusMessage = "Watching \(names)"
        }
    }

    private func arrive(at place: GardenPlace) {
        let key = "experience.welcome.\(place.id.uuidString)"
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Date().timeIntervalSince(last) < arrivalCooldown {
            return
        }
        UserDefaults.standard.set(Date(), forKey: key)
        welcomePlace = place
    }

    fileprivate func handleAuthorization(_ status: CLAuthorizationStatus) {
        authorization = status
        switch status {
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            registerRegions()
        case .authorizedAlways:
            registerRegions()
        case .denied, .restricted:
            statusMessage = "Location is off. The welcome appears when you allow it."
        default:
            break
        }
    }

    fileprivate func handleEntered(identifier: String) {
        guard let place = places.first(where: { $0.id.uuidString == identifier }) else { return }
        arrive(at: place)
    }

    fileprivate func handleMonitoringFailure(_ error: Error) {
        statusMessage = error.localizedDescription
    }
}

private enum GardenPlaceLoader {
    static func load() -> [GardenPlace] {
        guard
            let url = Bundle.main.url(forResource: "garden-places", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let places = try? GardenPlaceCatalog.load(from: data)
        else { return [] }
        return places
    }
}

extension GardenGeofenceMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            handleAuthorization(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier
        Task { @MainActor in
            handleEntered(identifier: identifier)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard state == .inside else { return }
        let identifier = region.identifier
        Task { @MainActor in
            handleEntered(identifier: identifier)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Task { @MainActor in
            handleMonitoringFailure(error)
        }
    }
}
