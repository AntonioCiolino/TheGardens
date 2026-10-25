import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import GardensCore
import UIKit

struct CoreImageQRCodeGenerator: QRCodeGenerating {
    func makeQRCodeImageData(from payloadString: String, dimension: Int) throws -> Data {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payloadString.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else {
            throw QRRenderError.generationFailed
        }

        let scale = CGFloat(dimension) / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw QRRenderError.generationFailed
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let png = uiImage.pngData() else {
            throw QRRenderError.encodingFailed
        }
        return png
    }
}

enum QRRenderError: Error {
    case generationFailed
    case encodingFailed
}
