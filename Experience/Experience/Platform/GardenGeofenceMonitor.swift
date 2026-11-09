import Foundation
import CoreLocation
import ExperienceCore

/// Watches one circular region per enabled place. Does not call `startUpdatingLocation`.
@MainActor
final class GardenGeofenceMonitor: NSObject, ObservableObject {
    @Published private(set) var welcomePlace: GardenPlace?
    /// Bumps when Preview welcome should play the splash again.
    @Published private(set) var splashReplayID = 0
    @Published private(set) var authorization = CLAuthorizationStatus.notDetermined
    @Published private(set) var statusMessage: String?

    private let manager = CLLocationManager()
    private let cloudRepo = CloudKitFeedRepository()
    private var places: [GardenPlace] = []
    /// Regions still waiting for `didDetermineState` in the current presence check.
    private var pendingStateIdentifiers: Set<String> = []
    /// Identifiers reported `.inside` during the current presence check.
    private var insideIdentifiers: Set<String> = []
    private var presenceSweepActive = false

    func start() {
        places = GardenPlaceLoader.cached() ?? GardenPlaceLoader.bundled()
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
        Task { await refreshFromCloud() }
    }

    /// Pulls the fence list from iCloud. The phone keeps watching the last list until that returns.
    private func refreshFromCloud() async {
        let remote: [GardenPlace]
        do {
            remote = try await cloudRepo.fetchOrSeedPlaces(GardenPlaceLoader.bundled())
        } catch {
            return
        }
        GardenPlaceLoader.save(remote)
        guard remote != places else { return }
        places = remote
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            registerRegions()
        default:
            break
        }
    }

    /// Asks iOS whether the device is already inside each monitored region.
    /// Launch does this from `registerRegions`. Foregrounding calls this again.
    func appBecameActive() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            Task { await refreshFromCloud() }
            if manager.monitoredRegions.isEmpty {
                registerRegions()
            } else {
                requestPresence()
            }
        default:
            break
        }
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
        splashReplayID += 1
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
        }
        if wanted.isEmpty {
            statusMessage = "No garden locations are turned on yet."
        } else {
            let names = wanted.map(\.name).joined(separator: ", ")
            statusMessage = "Watching \(names)"
        }
        requestPresence()
    }

    /// One state query per monitored region. No continuous location updates.
    private func requestPresence() {
        let wantedIDs = Set(GardenPlaceCatalog.placesToMonitor(places).map(\.id.uuidString))
        let regions = manager.monitoredRegions.filter { wantedIDs.contains($0.identifier) }
        guard !regions.isEmpty else { return }
        presenceSweepActive = true
        pendingStateIdentifiers = Set(regions.map(\.identifier))
        insideIdentifiers = []
        for region in regions {
            manager.requestState(for: region)
        }
    }

    /// Home wins when several regions contain the device. Otherwise the first
    /// inside place in catalog order. One assignment, so the bounce is not stacked.
    private func resolvePresence() {
        guard presenceSweepActive else { return }
        let monitored = GardenPlaceCatalog.placesToMonitor(places)
        let inside = monitored.filter { insideIdentifiers.contains($0.id.uuidString) }
        if let home = inside.first(where: { $0.name == "Home" }) {
            welcomePlace = home
            finishPresenceSweep()
            return
        }
        guard pendingStateIdentifiers.isEmpty else { return }
        finishPresenceSweep()
        if let place = inside.first {
            welcomePlace = place
        }
    }

    private func finishPresenceSweep() {
        presenceSweepActive = false
        pendingStateIdentifiers.removeAll()
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
        guard places.contains(where: { $0.id.uuidString == identifier }) else { return }
        if presenceSweepActive {
            insideIdentifiers.insert(identifier)
            resolvePresence()
            return
        }
        guard welcomePlace == nil,
              let place = places.first(where: { $0.id.uuidString == identifier })
        else { return }
        welcomePlace = place
    }

    fileprivate func handleRegionState(_ state: CLRegionState, identifier: String) {
        guard presenceSweepActive, pendingStateIdentifiers.contains(identifier) else { return }
        switch state {
        case .inside:
            pendingStateIdentifiers.remove(identifier)
            insideIdentifiers.insert(identifier)
        case .outside:
            pendingStateIdentifiers.remove(identifier)
            insideIdentifiers.remove(identifier)
        case .unknown:
            return
        @unknown default:
            return
        }
        resolvePresence()
    }

    fileprivate func handleMonitoringFailure(_ error: Error, identifier: String?) {
        statusMessage = error.localizedDescription
        guard presenceSweepActive, let identifier else { return }
        pendingStateIdentifiers.remove(identifier)
        resolvePresence()
    }
}

private enum GardenPlaceLoader {
    private static let cacheKey = "experience.gardenPlaces"

    static func bundled() -> [GardenPlace] {
        guard
            let url = Bundle.main.url(forResource: "garden-places", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let places = try? GardenPlaceCatalog.load(from: data)
        else { return [] }
        return places
    }

    static func cached() -> [GardenPlace]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? GardenPlaceCatalog.load(from: data)
    }

    static func save(_ places: [GardenPlace]) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
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
        let identifier = region.identifier
        Task { @MainActor in
            handleRegionState(state, identifier: identifier)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let identifier = region?.identifier
        Task { @MainActor in
            handleMonitoringFailure(error, identifier: identifier)
        }
    }
}
