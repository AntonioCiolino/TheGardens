import XCTest
@testable import ExperienceCore

final class GardenPlaceCatalogTests: XCTestCase {
    func testSeparateCentersBothMonitor() throws {
        let places = try GardenPlaceCatalog.load(from: Data(catalog.utf8))
        let monitored = GardenPlaceCatalog.placesToMonitor(places)
        XCTAssertEqual(monitored.map(\.name), ["Home", "The Gardens"])
        XCTAssertEqual(monitored[0].latitude, 39.1290784)
        XCTAssertEqual(monitored[0].longitude, -84.4746211)
        XCTAssertEqual(monitored[1].latitude, 39.1289487)
        XCTAssertEqual(monitored[1].longitude, -84.4768209)
        XCTAssertNotEqual(monitored[0].latitude, monitored[1].latitude)
        XCTAssertNotEqual(monitored[0].longitude, monitored[1].longitude)
    }

    func testParkWithoutCoordinatesStaysOff() throws {
        let places = try GardenPlaceCatalog.load(from: Data(catalog.utf8))
        let park = try XCTUnwrap(places.first { $0.name == "The Garden Park" })
        XCTAssertFalse(park.enabled)
        XCTAssertNil(park.latitude)
        XCTAssertNil(park.longitude)
        XCTAssertFalse(park.isMonitorable)
        XCTAssertFalse(GardenPlaceCatalog.placesToMonitor(places).contains { $0.name == "The Garden Park" })
    }

    func testCapsAtTwentyRegions() {
        let places = (0..<25).map { index in
            GardenPlace(
                id: UUID(),
                name: "Place \(index)",
                latitude: 39.0 + Double(index) * 0.01,
                longitude: -84.0,
                radiusMeters: 100,
                enabled: true
            )
        }
        XCTAssertEqual(GardenPlaceCatalog.placesToMonitor(places).count, 20)
    }

    func testTinyRadiusAndNullIslandAreSkipped() {
        let tiny = GardenPlace(id: UUID(), name: "Tiny", latitude: 39.1, longitude: -84.4, radiusMeters: 40, enabled: true)
        let island = GardenPlace(id: UUID(), name: "Island", latitude: 0, longitude: 0, radiusMeters: 150, enabled: true)
        XCTAssertTrue(GardenPlaceCatalog.placesToMonitor([tiny, island]).isEmpty)
    }

    private let catalog = """
    [
      {
        "id": "B7E2A1C4-6D58-4F0A-9C31-8A4E2F6B1D70",
        "name": "Home",
        "latitude": 39.1290784,
        "longitude": -84.4746211,
        "radiusMeters": 100,
        "enabled": true
      },
      {
        "id": "C3A91F08-2E47-4B6D-A15C-7D90E4F82B16",
        "name": "The Gardens",
        "latitude": 39.1289487,
        "longitude": -84.4768209,
        "radiusMeters": 100,
        "enabled": true
      },
      {
        "id": "D4B82E19-3F58-4C7E-B26D-8E01F5A93C27",
        "name": "The Garden Park",
        "radiusMeters": 100,
        "enabled": false,
        "note": "Needs its own pin."
      }
    ]
    """
}
