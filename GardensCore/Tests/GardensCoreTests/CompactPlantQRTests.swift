import XCTest
@testable import GardensCore

final class CompactPlantQRTests: XCTestCase {
    func testRoundTripContainsIDAndNameOnly() throws {
        let id = UUID()
        let qr = CompactPlantQR(instanceID: id, name: "Snake Plant")
        let encoded = try qr.encodedString()

        XCTAssertLessThan(encoded.utf8.count, 200)
        XCTAssertTrue(encoded.contains(id.uuidString))
        XCTAssertTrue(encoded.contains("Snake Plant"))
        XCTAssertFalse(encoded.contains(#""c":"#))
        XCTAssertFalse(encoded.lowercased().contains("vendor"))
        XCTAssertFalse(encoded.lowercased().contains("care"))

        let decoded = try CompactPlantQR.decode(encoded)
        XCTAssertEqual(decoded.instanceID, id)
        XCTAssertEqual(decoded.name, "Snake Plant")
    }

    func testBareUUIDStillResolvesAsID() {
        let id = UUID()
        XCTAssertEqual(CompactPlantQR.instanceID(fromScanned: id.uuidString), id)
    }
}
