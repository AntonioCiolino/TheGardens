import XCTest
@testable import GardensCore

final class PlantCatalogMatcherTests: XCTestCase {
    func testFindsExistingIgnoringCaseAndWhitespace() {
        let existing = PlantCatalogItem(name: "Snake Plant", genus: "Dracaena")
        let match = PlantCatalogMatcher.findExisting(
            name: "  snake plant ",
            genus: "DRACAENA",
            in: [existing]
        )
        XCTAssertEqual(match?.id, existing.id)
    }

    func testNoMatchWhenGenusDiffers() {
        let existing = PlantCatalogItem(name: "Snake Plant", genus: "Dracaena")
        let match = PlantCatalogMatcher.findExisting(
            name: "Snake Plant",
            genus: "Sansevieria",
            in: [existing]
        )
        XCTAssertNil(match)
    }
}
