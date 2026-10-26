import Foundation

/// A reference photo and editable care notes for a plant name.
public struct PlantReferenceSuggestion: Hashable, Sendable {
    /// Botanical name to drop into the genus field, such as "Dracaena trifasciata".
    public var scientificName: String
    public var careProfile: PlantCareProfile
    public var photoData: Data?
    public var photoCredit: String
    /// Shown under the care fields so staff know the notes are suggestions.
    public var careNote: String

    public init(
        scientificName: String,
        careProfile: PlantCareProfile,
        photoData: Data?,
        photoCredit: String,
        careNote: String
    ) {
        self.scientificName = scientificName
        self.careProfile = careProfile
        self.photoData = photoData
        self.photoCredit = photoCredit
        self.careNote = careNote
    }
}

public enum PlantLookupError: LocalizedError, Equatable {
    case noMatch
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .noMatch: return "No reference found for that name."
        case .badResponse: return "The plant reference didn’t respond."
        }
    }
}

/// Looks up a real plant photo and a short care summary on Wikipedia.
public struct WikipediaPlantLookup: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func lookup(name: String, genus: String) async throws -> PlantReferenceSuggestion {
        let terms = Self.searchTerms(name: name, genus: genus)
        guard !terms.isEmpty else { throw PlantLookupError.noMatch }

        var titles: [String] = []
        var sawResponse = false
        for term in terms {
            do {
                let hits = try await search(term)
                sawResponse = true
                for title in Self.rankedTitles(in: hits) where !titles.contains(title) {
                    titles.append(title)
                }
            } catch {
                continue
            }
        }
        guard sawResponse else { throw PlantLookupError.badResponse }

        for title in titles {
            let page = try await page(titled: title)
            guard let extract = page.extract, Self.isPlantDescription(extract) else { continue }
            return try await suggestion(for: page, extract: extract)
        }
        throw PlantLookupError.noMatch
    }

    /// Loads one Wikipedia article by the title the model chose. Redirects are followed.
    public func lookup(title: String) async throws -> PlantReferenceSuggestion {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { throw PlantLookupError.noMatch }
        let page = try await page(titled: trimmed)
        guard let extract = page.extract, Self.isPlantDescription(extract) else {
            throw PlantLookupError.noMatch
        }
        return try await suggestion(for: page, extract: extract)
    }

    /// Genus and name are searched separately so a person’s name cannot pull the plant query off course.
    static func searchTerms(name: String, genus: String) -> [String] {
        var terms: [String] = []
        for raw in [genus, name] {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard term.count >= 3 else { continue }
            guard !terms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) else { continue }
            terms.append(term)
        }
        return terms
    }

    static func rankedTitles(in hits: [SearchHit]) -> [String] {
        hits
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0.title)
    }

    static func isPlantDescription(_ text: String) -> Bool {
        let plain = strip(text).lowercased()
        if isPerson(plain) { return false }
        let phrases = [
            "species of", "genus of", "flowering plant", "houseplant", "succulent",
            "cultivar", "plant in the", "family ", "fern", "cactus", "shrub", "vine"
        ]
        return phrases.contains { plain.contains($0) }
    }

    private func suggestion(for page: ParsedPage, extract: String) async throws -> PlantReferenceSuggestion {
        var photo: Data?
        if let source = page.thumbnailURL, let url = URL(string: source) {
            photo = try? await data(from: url)
        }

        let credit = "Reference photo · Wikipedia · \(page.title)"
        return PlantReferenceSuggestion(
            scientificName: page.title,
            careProfile: Self.careProfile(from: extract),
            photoData: photo,
            photoCredit: photo == nil ? "" : credit,
            careNote: "Care notes are suggestions from the Wikipedia summary. Edit them before saving."
        )
    }

    static func bestTitle(in hits: [SearchHit]) -> String? {
        rankedTitles(in: hits).first
    }

    static func careProfile(from extract: String) -> PlantCareProfile {
        let sentences = extract
            .replacingOccurrences(of: "\n", with: " ")
            .split { ".!?".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 12 }
        let care = sentences.prefix(3).joined(separator: ". ")
        let watering = matching(sentences, words: ["water", "moist", "drought", "soil", "dry"])
        let health = matching(sentences, words: ["leaf", "pest", "light", "sun", "yellow", "disease", "rot"])
        return PlantCareProfile(
            careInstructions: String((care.isEmpty ? extract : care + ".").prefix(700)),
            wateringCheckGuidance: watering.isEmpty
                ? "Check the soil before watering, then edit this note for your nursery."
                : watering + ".",
            healthCheckGuidance: health.isEmpty
                ? "Look over the leaves and stems, then edit this note for your nursery."
                : health + "."
        )
    }

    static func parseSearch(_ data: Data) throws -> [SearchHit] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let query = root["query"] as? [String: Any],
            let rows = query["search"] as? [[String: Any]]
        else { throw PlantLookupError.badResponse }
        return rows.compactMap { row in
            guard let title = row["title"] as? String, !title.isEmpty else { return nil }
            return SearchHit(title: title, snippet: row["snippet"] as? String ?? "")
        }
    }

    static func parsePage(_ data: Data) throws -> ParsedPage {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let query = root["query"] as? [String: Any],
            let pages = query["pages"] as? [String: Any]
        else { throw PlantLookupError.badResponse }
        for (_, value) in pages {
            guard let page = value as? [String: Any], page["missing"] == nil else { continue }
            guard let title = page["title"] as? String else { continue }
            let thumb = (page["thumbnail"] as? [String: Any])?["source"] as? String
            return ParsedPage(title: title, extract: page["extract"] as? String, thumbnailURL: thumb)
        }
        throw PlantLookupError.noMatch
    }

    struct SearchHit: Equatable {
        var title: String
        var snippet: String
    }

    struct ParsedPage {
        var title: String
        var extract: String?
        var thumbnailURL: String?
    }

    private func search(_ query: String) async throws -> [SearchHit] {
        var parts = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        parts.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: "5"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "utf8", value: "1"),
        ]
        guard let url = parts.url else { throw PlantLookupError.badResponse }
        return try Self.parseSearch(try await data(from: url))
    }

    private func page(titled title: String) async throws -> ParsedPage {
        var parts = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        parts.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "extracts|pageimages"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "pithumbsize", value: "1000"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "utf8", value: "1"),
        ]
        guard let url = parts.url else { throw PlantLookupError.badResponse }
        return try Self.parsePage(try await data(from: url))
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Gardens/1.0 (plant intake reference lookup)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlantLookupError.badResponse
        }
        return data
    }

    private static func score(_ hit: SearchHit) -> Int {
        if hit.title.lowercased().contains("disambiguation") || hit.title.hasPrefix("List of") { return 0 }
        let plain = strip(hit.title + " " + hit.snippet)
        guard isPlantDescription(plain) else { return 0 }
        let lower = plain.lowercased()
        var score = 2
        if lower.contains("species of") || lower.contains("genus of") || lower.contains("flowering plant") {
            score += 6
        }
        return score
    }

    private static func isPerson(_ text: String) -> Bool {
        let words = ["singer", "songwriter", "musician", "guitarist", "vocalist", "drummer", "actor", "actress", "footballer", "politician", "born"]
        return words.contains { text.contains($0) }
    }

    private static func strip(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private static func matching(_ sentences: [String], words: [String]) -> String {
        sentences.filter { sentence in
            let lower = sentence.lowercased()
            return words.contains { lower.contains($0) }
        }
        .prefix(2)
        .joined(separator: ". ")
    }
}
