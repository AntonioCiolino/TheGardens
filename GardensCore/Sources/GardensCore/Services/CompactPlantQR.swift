import Foundation

/// Two-layer QR content for one plant instance.
///
/// 1. **ID** (`i`) — looks up the full rich record (care, watering, health, history).
/// 2. **Core fields** — tiny offline snapshot (name, color, …) so a scanner
///    can show basics without a database round-trip.
///
/// Wire format (UTF-8 JSON, short keys, sorted): typically well under 200 bytes,
/// hard-capped below 1 KB for QR Version ≤ ~10 capacity.
///
/// Example:
/// ```
/// {"c":"variegated green","i":"A1B2C3D4-...","n":"Snake Plant","v":1}
/// ```
public struct CompactPlantQR: Hashable, Codable, Sendable {
    public static let schemaVersion = 1
    public static let maxEncodedUTF8Bytes = 900

    /// Schema version.
    public var v: Int
    /// Plant instance UUID (authoritative link into the data store).
    public var i: UUID
    /// Plant display name (from catalog).
    public var n: String
    /// Simple color / foliage note for offline display.
    public var c: String

    public var instanceID: UUID { i }
    public var name: String { n }
    public var color: String { c }

    public init(instanceID: UUID, name: String, color: String) {
        self.v = Self.schemaVersion
        self.i = instanceID
        self.n = Self.clip(name, maxChars: 80)
        self.c = Self.clip(color, maxChars: 40)
    }

    public init(detail: PlantInstanceDetail) {
        self.init(
            instanceID: detail.instance.id,
            name: detail.catalog.name,
            color: detail.catalog.color
        )
    }

    // MARK: - Encode / decode

    public func encodedString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maxEncodedUTF8Bytes else {
            throw CompactPlantQRError.payloadTooLarge(data.count)
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw CompactPlantQRError.encodingFailed
        }
        return string
    }

    public static func decode(_ scanned: String) throws -> CompactPlantQR {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw CompactPlantQRError.invalidPayload
        }
        let decoded = try JSONDecoder().decode(CompactPlantQR.self, from: data)
        guard decoded.v == schemaVersion else {
            throw CompactPlantQRError.unsupportedVersion(decoded.v)
        }
        return decoded
    }

    /// Prefer the embedded ID; also accept a bare UUID for older/manual codes.
    public static func instanceID(fromScanned string: String) -> UUID? {
        if let compact = try? decode(string) {
            return compact.instanceID
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: trimmed)
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
