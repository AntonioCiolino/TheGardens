import Foundation
import GardensCore
import UIKit

struct CoreImageQRCodeGenerator: QRCodeGenerating {
    func makeQRCodeImageData(from payloadString: String, dimension: Int) throws -> Data {
        guard let image = BrandedQRImage.image(payload: payloadString, side: CGFloat(dimension)),
              let png = image.pngData() else {
            throw QRRenderError.generationFailed
        }
        return png
    }
}

enum QRRenderError: Error {
    case generationFailed
    case encodingFailed
}
