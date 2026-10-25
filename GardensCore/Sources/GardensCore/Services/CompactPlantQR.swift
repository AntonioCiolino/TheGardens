import Foundation

/// Plant label QR payload.
///
/// Wire format is a **Gardens deep link** so:
/// 1. The magic scheme `gardens://` identifies the code as ours.
/// 2. The iPhone Camera app can offer **Open in Gardens** when scanned.
///
/// Example:
/// ```
/// gardens://plant/A1B2C3D4-E5F6-7890-ABCD-EF1234567890?n=Snake%20Plant
/// ```
///
/// Still accepts legacy compact JSON and bare UUIDs when decoding.
public struct CompactPlantQR: Hashable, Sendable {
    public static let urlScheme = "gardens"
    public static let plantHost = "plant"
    public static let maxEncodedUTF8Bytes = 900

    /// Magic prefix / scheme that marks a Gardens plant label.
    public static let magicHeader = "gardens"

    public var instanceID: UUID
    public var name: String

    public init(instanceID: UUID, name: String = "") {
        self.instanceID = instanceID
        self.name = Self.clip(name, maxChars: 80)
    }

    public init(detail: PlantInstanceDetail) {
        self.init(instanceID: detail.instance.id, name: detail.catalog.name)
    }

    /// Deep link written into the QR symbol.
    public var deepLinkURL: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = Self.plantHost
        components.path = "/\(instanceID.uuidString)"
        if !name.isEmpty {
            components.queryItems = [URLQueryItem(name: "n", value: name)]
        }
        return components.url ?? URL(string: "\(Self.urlScheme)://\(Self.plantHost)/\(instanceID.uuidString)")!
    }

    // MARK: - Encode / decode

    public func encodedString() throws -> String {
        let string = deepLinkURL.absoluteString
        guard string.utf8.count <= Self.maxEncodedUTF8Bytes else {
            throw CompactPlantQRError.payloadTooLarge(string.utf8.count)
        }
        return string
    }

    public static func decode(_ scanned: String) throws -> CompactPlantQR {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromURL = decodeDeepLink(trimmed) {
            return fromURL
        }
        if let fromLegacy = decodeLegacyJSON(trimmed) {
            return fromLegacy
        }
        if let id = UUID(uuidString: trimmed) {
            return CompactPlantQR(instanceID: id)
        }
        throw CompactPlantQRError.invalidPayload
    }

    /// Extract instance ID from a scanned QR (deep link, legacy JSON, or bare UUID).
    public static func instanceID(fromScanned string: String) -> UUID? {
        try? decode(string).instanceID
    }

    /// True when the payload is clearly a Gardens label (scheme / magic header).
    public static func isGardensPayload(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.lowercased() == urlScheme {
            return true
        }
        if trimmed.lowercased().hasPrefix("\(magicHeader):") { return true }
        // Legacy JSON always included instance id — treat as gardens if decodable.
        return (try? decode(trimmed)) != nil
    }

    private static func decodeDeepLink(_ string: String) -> CompactPlantQR? {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == urlScheme,
              (url.host?.lowercased() == plantHost || url.host == nil)
        else { return nil }

        // gardens://plant/<uuid>  or  gardens:///plant/<uuid>
        let pathParts = url.pathComponents.filter { $0 != "/" }
        let idString: String?
        if url.host?.lowercased() == plantHost {
            idString = pathParts.first
        } else if pathParts.count >= 2, pathParts[0].lowercased() == plantHost {
            idString = pathParts[1]
        } else {
            idString = pathParts.last
        }

        guard let idString, let id = UUID(uuidString: idString) else { return nil }
        let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "n" })?
            .value ?? ""
        return CompactPlantQR(instanceID: id, name: name)
    }

    private static func decodeLegacyJSON(_ string: String) -> CompactPlantQR? {
        guard let data = string.data(using: .utf8) else { return nil }
        struct Legacy: Decodable {
            var v: Int?
            var i: UUID
            var n: String?
        }
        guard let legacy = try? JSONDecoder().decode(Legacy.self, from: data) else { return nil }
        return CompactPlantQR(instanceID: legacy.i, name: legacy.n ?? "")
    }

    private static func clip(_ value: String, maxChars: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<end])
    }
}

public enum CompactPlantQRError: Error, Sendable {
    case encodingFailed
    case invalidPayload
    case unsupportedVersion(Int)
    case payloadTooLarge(Int)
}

/// Platform implementations (Core Image on iOS, etc.) conform to this.
public protocol QRCodeGenerating: Sendable {
    func makeQRCodeImageData(from payloadString: String, dimension: Int) throws -> Data
}

/// Platform print adapters; core never imports UIKit.
public protocol PlantLabelPrinting: Sendable {
    func printLabel(title: String, subtitle: String, qrImageData: Data) async throws
}

public enum PlantQRError: Error, Sendable {
    case invalidCode
    case unknownInstance
}
