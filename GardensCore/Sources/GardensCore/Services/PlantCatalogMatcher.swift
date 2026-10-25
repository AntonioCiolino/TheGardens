import Foundation

/// Pure matching rules for reusing catalog rows instead of duplicating types.
public enum PlantCatalogMatcher: Sendable {
    public static func matchKey(name: String, genus: String) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let g = genus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(n)|\(g)"
    }

    /// Finds an existing catalog item with the same name + genus (case/whitespace-insensitive).
    public static func findExisting(
        name: String,
        genus: String,
        in catalog: [PlantCatalogItem]
    ) -> PlantCatalogItem? {
        let key = matchKey(name: name, genus: genus)
        return catalog.first { $0.matchKey == key }
    }
}
