import Foundation
import UIKit
import GardensCore

/// Wikipedia photo, plus Apple Intelligence care notes when the phone can run them.
enum PlantReferenceLoader {
    static func load(name: String, genus: String) async throws -> PlantReferenceSuggestion {
        var suggestion = try await WikipediaPlantLookup().lookup(name: name, genus: genus)
        if let photo = suggestion.photoData {
            suggestion = PlantReferenceSuggestion(
                scientificName: suggestion.scientificName,
                careProfile: suggestion.careProfile,
                photoData: jpeg(photo),
                photoCredit: suggestion.photoCredit,
                careNote: suggestion.careNote
            )
        }
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if let guide = try? await ApplePlantGuide.enrich(
                name: name,
                genus: genus,
                wikipediaTitle: suggestion.scientificName,
                referenceText: suggestion.careProfile.careInstructions
            ) {
                suggestion = PlantReferenceSuggestion(
                    scientificName: guide.scientificName.isEmpty ? suggestion.scientificName : guide.scientificName,
                    careProfile: guide.careProfile,
                    photoData: suggestion.photoData,
                    photoCredit: suggestion.photoCredit,
                    careNote: "Care notes are suggestions from Apple Intelligence. Edit them before saving."
                )
            }
        }
        #endif
        return suggestion
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
    static func enrich(
        name: String,
        genus: String,
        wikipediaTitle: String,
        referenceText: String
    ) async throws -> (scientificName: String, careProfile: PlantCareProfile) {
        guard case .available = SystemLanguageModel.default.availability else {
            throw PlantLookupError.noMatch
        }
        let session = LanguageModelSession(instructions: """
            You write short care notes for a plant nursery. Use the reference text. \
            Keep the species that reference names. Each note is one or two sentences a staff member can edit.
            """)
        let response = try await session.respond(
            to: """
            Common name: \(name)
            Genus already typed: \(genus)
            Wikipedia title: \(wikipediaTitle)
            Reference:
            \(referenceText.prefix(1500))
            """,
            generating: NurseryGuide.self
        )
        let guide = response.content
        return (
            guide.scientificName.trimmingCharacters(in: .whitespacesAndNewlines),
            PlantCareProfile(
                careInstructions: guide.careInstructions,
                wateringCheckGuidance: guide.wateringCheckGuidance,
                healthCheckGuidance: guide.healthCheckGuidance
            )
        )
    }
}

@available(iOS 26.0, *)
@Generable
private struct NurseryGuide {
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
