import Foundation
import UIKit
import GardensCore

/// Apple Intelligence picks the Wikipedia article. The photo is loaded from that page.
enum PlantReferenceLoader {
    static func load(name: String, genus: String) async throws -> PlantReferenceSuggestion {
        let wiki = WikipediaPlantLookup()
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if let guide = try? await ApplePlantGuide.resolve(name: name, genus: genus),
               let page = try? await wiki.lookup(title: guide.wikipediaTitle) {
                return compose(page: page, guide: guide)
            }
        }
        #endif
        var suggestion = try await wiki.lookup(name: name, genus: genus)
        if let photo = suggestion.photoData {
            suggestion = PlantReferenceSuggestion(
                scientificName: suggestion.scientificName,
                careProfile: suggestion.careProfile,
                photoData: jpeg(photo),
                photoCredit: suggestion.photoCredit,
                careNote: suggestion.careNote
            )
        }
        return suggestion
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func compose(page: PlantReferenceSuggestion, guide: NurseryGuide) -> PlantReferenceSuggestion {
        PlantReferenceSuggestion(
            scientificName: text(guide.scientificName, or: page.scientificName),
            careProfile: PlantCareProfile(
                careInstructions: text(guide.careInstructions, or: page.careProfile.careInstructions),
                wateringCheckGuidance: text(guide.wateringCheckGuidance, or: page.careProfile.wateringCheckGuidance),
                healthCheckGuidance: text(guide.healthCheckGuidance, or: page.careProfile.healthCheckGuidance)
            ),
            photoData: page.photoData.map(jpeg),
            photoCredit: page.photoCredit,
            careNote: "Care notes are suggestions from Apple Intelligence. Edit them before saving."
        )
    }
    #endif

    private static func text(_ value: String, or fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func jpeg(_ data: Data) -> Data {
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.82) else {
            return data
        }
        return jpeg
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
private enum ApplePlantGuide {
    static func resolve(name: String, genus: String) async throws -> NurseryGuide {
        guard case .available = SystemLanguageModel.default.availability else {
            throw PlantLookupError.noMatch
        }
        let session = LanguageModelSession(instructions: """
            You choose the English Wikipedia article for a plant a nursery worker typed. \
            The name box and the genus box are often swapped. One box may be a person’s name or other junk. \
            Pick the plant they mean. Return that plant’s Wikipedia article title, not a person, band, or piece of clothing. \
            Robert Plant is a singer. Snake plant is the article Dracaena trifasciata. \
            If neither box names a plant, leave the Wikipedia title empty.
            """)
        let response = try await session.respond(
            to: """
            Name box: \(name)
            Genus box: \(genus)
            """,
            generating: NurseryGuide.self
        )
        let guide = response.content
        guard !guide.wikipediaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlantLookupError.noMatch
        }
        return guide
    }
}

@available(iOS 26.0, *)
@Generable
struct NurseryGuide {
    @Guide(description: "Exact English Wikipedia article title for the plant, such as Dracaena trifasciata. Never a person.")
    var wikipediaTitle: String
    @Guide(description: "Botanical name, genus and species when known, such as Dracaena trifasciata")
    var scientificName: String
    @Guide(description: "One or two sentences on everyday care")
    var careInstructions: String
    @Guide(description: "How staff should check if it needs water")
    var wateringCheckGuidance: String
    @Guide(description: "What to look for in a health check")
    var healthCheckGuidance: String
}
#endif
