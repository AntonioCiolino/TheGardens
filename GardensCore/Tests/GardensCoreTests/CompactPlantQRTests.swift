import XCTest
@testable import GardensCore

final class CompactPlantQRTests: XCTestCase {
    func testEncodesGardensDeepLink() throws {
        let id = UUID()
        let qr = CompactPlantQR(instanceID: id, name: "Snake Plant")
        let encoded = try qr.encodedString()

        XCTAssertTrue(encoded.hasPrefix("gardens://plant/"))
        XCTAssertTrue(encoded.contains(id.uuidString))
        XCTAssertTrue(encoded.contains("Snake"))
        XCTAssertTrue(CompactPlantQR.isGardensPayload(encoded))

        let decoded = try CompactPlantQR.decode(encoded)
        XCTAssertEqual(decoded.instanceID, id)
        XCTAssertEqual(decoded.name, "Snake Plant")
    }

    func testLegacyJSONStillDecodes() {
        let id = UUID()
        let legacy = #"{"i":"\#(id.uuidString)","n":"Monstera","v":1}"#
        XCTAssertEqual(CompactPlantQR.instanceID(fromScanned: legacy), id)
    }

    func testBareUUIDStillResolvesAsID() {
        let id = UUID()
        XCTAssertEqual(CompactPlantQR.instanceID(fromScanned: id.uuidString), id)
    }
}
