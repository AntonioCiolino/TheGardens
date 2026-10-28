import CoreImage
import Foundation
import UIKit

struct PlantLabelJob: Identifiable, Hashable {
    var id: UUID
    var title: String
    var subtitle: String
    var qrPayload: String
}

struct LabelPrintRequest: Identifiable {
    let id = UUID()
    var jobs: [PlantLabelJob]
}

enum SupvanLabel {
    static let headDots = 384
    static let bytesPerLine = 48
    /// Blank feed before and after the artwork so it sits in the middle of a large round label.
    static let marginDots: UInt16 = 50
    static let printSpeed: UInt16 = 8

    /// Column-major raster for a 48 mm / 384-dot T50 printhead.
    /// The test print mirrored the name, so dots run from the right side of the head.
    /// Artwork is 1.5× the first guess so it fills a large circular label.
    static func raster(title: String, subtitle: String, qrPayload: String) throws -> (data: [UInt8], columns: UInt16) {
        let contentWidth = 360
        let contentHeight = 300
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: contentWidth, height: contentHeight),
            format: format
        )
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight))

            let titleFont = UIFont.systemFont(ofSize: 33, weight: .bold)
            let subtitleFont = UIFont.systemFont(ofSize: 21, weight: .regular)
            let titleRect = CGRect(x: 12, y: 6, width: contentWidth - 24, height: 42)
            let subtitleRect = CGRect(x: 12, y: 50, width: contentWidth - 24, height: 28)
            (title as NSString).draw(
                in: titleRect,
                withAttributes: [
                    .font: titleFont,
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: centered
                ]
            )
            (subtitle as NSString).draw(
                in: subtitleRect,
                withAttributes: [
                    .font: subtitleFont,
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: centered
                ]
            )
            let qrSide: CGFloat = 210
            if let qr = qrImage(payload: qrPayload, points: qrSide) {
                let x = (CGFloat(contentWidth) - qrSide) / 2
                qr.draw(in: CGRect(x: x, y: 82, width: qrSide, height: qrSide))
            }
        }

        guard let cgImage = image.cgImage else {
            throw T50PrinterError.renderFailed
        }
        let width = cgImage.width
        let height = cgImage.height
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw T50PrinterError.renderFailed
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let columns = Int(marginDots) + height + Int(marginDots)
        var packed = [UInt8](repeating: 0, count: columns * bytesPerLine)
        let x0 = (headDots - width) / 2
        for y in 0..<height {
            let col = Int(marginDots) + y
            for x in 0..<width {
                let pixel = (y * width + x) * 4
                let dark = rgba[pixel] < 140
                if dark {
                    let dot = (headDots - 1) - (x0 + x)
                    let index = col * bytesPerLine + dot / 8
                    packed[index] |= 1 << (dot % 8)
                }
            }
        }
        return (packed, UInt16(columns))
    }

    static func printBuffers(raster: [UInt8], columns: UInt16) throws -> [[UInt8]] {
        let margin = marginDots
        let contentCols = columns > margin * 2 ? columns - margin * 2 : 0
        guard contentCols > 0 else { throw T50PrinterError.renderFailed }
        let stride = bytesPerLine
        let maxCols = 4074 / stride
        var chunks: [(start: Int, count: Int)] = []
        var remaining = Int(contentCols)
        var cursor = 0
        while remaining > 0 {
            let count = min(remaining, maxCols)
            chunks.append((cursor, count))
            cursor += count
            remaining -= count
        }
        let last = chunks.count - 1
        return try chunks.enumerated().map { index, chunk in
            let imgStart = (Int(margin) + chunk.start) * stride
            let imgEnd = imgStart + chunk.count * stride
            guard imgEnd <= raster.count else { throw T50PrinterError.renderFailed }
            let image = Array(raster[imgStart..<imgEnd])
            return makeBuffer(
                image: image,
                columns: UInt16(chunk.count),
                isFirst: index == 0,
                isLast: index == last
            )
        }
    }

    static func compressGrouped(_ buffers: [[UInt8]]) throws -> [(data: Data, speed: UInt16)] {
        guard !buffers.isEmpty else { throw T50PrinterError.renderFailed }
        var blocks: [(data: Data, speed: UInt16)] = []
        var rest = ArraySlice(buffers)
        while !rest.isEmpty {
            var take = min(4, rest.count)
            var compressed = Data()
            while true {
                let joined = Data(rest.prefix(take).joined())
                let zipped = try lzmaAlone(joined)
                if zipped.count <= 4096 {
                    compressed = zipped
                    break
                }
                if take == 1 {
                    throw T50PrinterError.compressedTooLarge
                }
                take -= 1
            }
            blocks.append((compressed, printSpeed))
            rest = rest.dropFirst(take)
        }
        return blocks
    }

    static func dataFrames(compressed: Data) -> [Data] {
        let payloadSize = 500
        let chunks = stride(from: 0, to: compressed.count, by: payloadSize).map { start -> Data in
            let end = min(start + payloadSize, compressed.count)
            return compressed.subdata(in: start..<end)
        }
        let total = UInt8(chunks.count)
        return chunks.enumerated().map { index, chunk in
            var packet = [UInt8](repeating: 0, count: 506)
            packet[0] = 0xAA
            packet[1] = 0xBB
            packet[4] = UInt8(index)
            packet[5] = total
            for (offset, byte) in chunk.enumerated() {
                packet[6 + offset] = byte
            }
            let sum = checksum(packet[4...])
            packet[2] = UInt8(sum & 0xFF)
            packet[3] = UInt8((sum >> 8) & 0xFF)

            var frame = [UInt8](repeating: 0, count: 512)
            frame[0] = 0x7E
            frame[1] = 0x5A
            frame[2] = 0xFC
            frame[3] = 0x01
            frame[4] = 0x10
            frame[5] = 0x02
            frame.replaceSubrange(6..<512, with: packet)
            return Data(frame)
        }
    }

    static func command(_ cmd: UInt8, blockSize: UInt16, blockCount: UInt16) -> Data {
        var packet = [UInt8](repeating: 0, count: 16)
        packet[0] = 0x7E
        packet[1] = 0x5A
        packet[2] = 0x0C
        packet[4] = 0x10
        packet[5] = 0x01
        packet[6] = 0xAA
        packet[7] = cmd
        packet[11] = 0x01
        packet[12] = UInt8(blockSize & 0xFF)
        packet[13] = UInt8((blockSize >> 8) & 0xFF)
        packet[14] = UInt8(blockCount & 0xFF)
        packet[15] = UInt8((blockCount >> 8) & 0xFF)
        let sum = checksum(packet[10..<16])
        packet[8] = UInt8(sum & 0xFF)
        packet[9] = UInt8((sum >> 8) & 0xFF)
        return Data(packet)
    }

    static func status(from frame: Data) -> SupvanStatus? {
        guard frame.count >= 18 else { return nil }
        let bytes = [UInt8](frame)
        return SupvanStatus(
            bufFull: bytes[14] & 0x01 != 0,
            deviceBusy: bytes[15] & 0x04 != 0,
            printing: bytes[16] & 0x40 != 0,
            labelMissing: bytes[17] & 0x01 != 0,
            coverOpen: bytes[16] & 0x08 != 0
        )
    }

    private static func makeBuffer(image: [UInt8], columns: UInt16, isFirst: Bool, isLast: Bool) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 4096)
        var flags: UInt8 = 0
        if isFirst { flags |= 0x02 }
        if isLast { flags |= 0x04 | 0x08 }
        buf[2] = flags
        let density: UInt8 = 4
        buf[3] = (density << 2) | (1 << 6)
        buf[4] = UInt8(columns & 0xFF)
        buf[5] = UInt8((columns >> 8) & 0xFF)
        buf[6] = UInt8(bytesPerLine)
        buf[8] = UInt8(marginDots & 0xFF)
        buf[9] = UInt8((marginDots >> 8) & 0xFF)
        buf[10] = buf[8]
        buf[11] = buf[9]
        buf[12] = density
        let copyCount = min(image.count, 4096 - 14)
        buf.replaceSubrange(14..<(14 + copyCount), with: image.prefix(copyCount))

        let dataEnd = Int(columns) * bytesPerLine + 14
        var sum = buf[2..<14].reduce(0) { $0 + Int($1) }
        var index = 255
        while index < min(dataEnd, 4096) {
            sum += Int(buf[index])
            index += 256
        }
        buf[0] = UInt8(sum & 0xFF)
        buf[1] = UInt8((sum >> 8) & 0xFF)
        return buf
    }

    private static func lzmaAlone(_ data: Data) throws -> Data {
        var outPointer: UnsafeMutablePointer<UInt8>?
        var outLen: Int = 0
        let rc = data.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 1 }
            return gardens_lzma_alone(base, data.count, &outPointer, &outLen)
        }
        guard rc == 0, let outPointer else {
            throw T50PrinterError.compressedTooLarge
        }
        let result = Data(bytes: outPointer, count: outLen)
        free(outPointer)
        return result
    }

    private static func checksum<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        bytes.reduce(UInt16(0)) { $0 &+ UInt16($1) }
    }

    private static var centered: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    private static func qrImage(payload: String, points: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = points / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct SupvanStatus {
    var bufFull: Bool
    var deviceBusy: Bool
    var printing: Bool
    var labelMissing: Bool
    var coverOpen: Bool
}

enum T50PrinterError: LocalizedError {
    case bluetoothOff
    case bluetoothDenied
    case notConnected
    case unrecognizedDevice
    case renderFailed
    case compressedTooLarge
    case timeout
    case printerRejected
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .bluetoothOff:
            return "Turn Bluetooth on to reach the T50M."
        case .bluetoothDenied:
            return "Gardens needs Bluetooth permission to print on the T50M."
        case .notConnected:
            return "Choose the T50M before printing."
        case .unrecognizedDevice:
            return "Gardens connected, but this device has no T50M print channel. Try another name in the list."
        case .renderFailed:
            return "Couldn’t draw the label."
        case .compressedTooLarge:
            return "The label is too large for one T50M transfer."
        case .timeout:
            return "The T50M didn’t answer. Keep it on and close to the phone, then try again."
        case .printerRejected:
            return "The T50M refused the label. Check that a tape is loaded and the cover is closed."
        case .writeFailed(let message):
            return message
        }
    }
}
