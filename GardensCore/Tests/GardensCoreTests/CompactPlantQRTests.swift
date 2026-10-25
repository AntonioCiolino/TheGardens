import XCTest
@testable import GardensCore

final class CompactPlantQRTests: XCTestCase {
    func testRoundTripContainsIDAndCoreFieldsOnly() throws {
        let id = UUID()
        let qr = CompactPlantQR(instanceID: id, name: "Snake Plant", color: "green")
        let encoded = try qr.encodedString()

        XCTAssertLessThan(encoded.utf8.count, 200)
        XCTAssertTrue(encoded.contains(id.uuidString))
        XCTAssertTrue(encoded.contains("Snake Plant"))
        XCTAssertTrue(encoded.contains("green"))
        XCTAssertFalse(encoded.lowercased().contains("vendor"))
        XCTAssertFalse(encoded.lowercased().contains("care"))
        XCTAssertFalse(encoded.lowercased().contains("water"))

        let decoded = try CompactPlantQR.decode(encoded)
        XCTAssertEqual(decoded.instanceID, id)
        XCTAssertEqual(decoded.name, "Snake Plant")
        XCTAssertEqual(decoded.color, "green")
    }

    func testBareUUIDStillResolvesAsID() {
        let id = UUID()
        XCTAssertEqual(CompactPlantQR.instanceID(fromScanned: id.uuidString), id)
    }
}
