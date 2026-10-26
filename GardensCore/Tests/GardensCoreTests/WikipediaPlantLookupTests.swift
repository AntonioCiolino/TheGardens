import XCTest
@testable import GardensCore

final class WikipediaPlantLookupTests: XCTestCase {
    func testSearchPrefersThePlantPage() throws {
        let data = """
        {"query":{"search":[
          {"title":"Snake","snippet":"Snake may refer to a limbless reptile."},
          {"title":"Dracaena trifasciata","snippet":"Dracaena trifasciata is a species of flowering plant in the family Asparagaceae."}
        ]}}
        """.data(using: .utf8)!
        let hits = try WikipediaPlantLookup.parseSearch(data)
        XCTAssertEqual(WikipediaPlantLookup.bestTitle(in: hits), "Dracaena trifasciata")
    }

    func testNameBobDoesNotSelectRobertPlant() {
        let hits = [
            WikipediaPlantLookup.SearchHit(
                title: "Robert Plant",
                snippet: "Robert Anthony Plant (born 20 August 1948) is an English singer and songwriter. He was the lead vocalist of Led Zeppelin."
            ),
            WikipediaPlantLookup.SearchHit(
                title: "Dracaena trifasciata",
                snippet: "Dracaena trifasciata is a species of flowering plant in the family Asparagaceae."
            ),
        ]
        XCTAssertEqual(WikipediaPlantLookup.bestTitle(in: hits), "Dracaena trifasciata")
        XCTAssertNil(
            WikipediaPlantLookup.bestTitle(in: [hits[0]])
        )
        XCTAssertEqual(
            WikipediaPlantLookup.searchTerms(name: "Bob", genus: "snake plant"),
            ["snake plant", "Bob"]
        )
        XCTAssertFalse(WikipediaPlantLookup.isPlantDescription(hits[0].snippet))
    }

    func testPageParseReadsExtractAndPhoto() throws {
        let data = """
        {"query":{"pages":{"4382912":{
          "title":"Dracaena trifasciata",
          "extract":"Dracaena trifasciata is a species of flowering plant. It is drought tolerant. Yellow leaves often mean too much water.",
          "thumbnail":{"source":"https://upload.wikimedia.org/example.jpg","width":1000,"height":800}
        }}}}
        """.data(using: .utf8)!
        let page = try WikipediaPlantLookup.parsePage(data)
        XCTAssertEqual(page.title, "Dracaena trifasciata")
        XCTAssertEqual(page.thumbnailURL, "https://upload.wikimedia.org/example.jpg")
        let care = WikipediaPlantLookup.careProfile(from: page.extract ?? "")
        XCTAssertTrue(care.careInstructions.contains("flowering plant"))
        XCTAssertTrue(care.wateringCheckGuidance.lowercased().contains("drought"))
        XCTAssertTrue(care.healthCheckGuidance.lowercased().contains("yellow"))
    }
}
