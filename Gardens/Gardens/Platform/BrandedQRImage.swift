import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum BrandedQRImage {
    /// Width ÷ height of `QRMonogram.png`, the G cut from the tall brand mark.
    static let markAspect: CGFloat = 714.0 / 1244.0

    /// QR at error-correction H with the G in the middle.
    /// H can rebuild about 30% of the code. The oval covers well under that,
    /// and only whole modules under it are cleared.
    static func image(payload: String, side: CGFloat) -> UIImage? {
        guard side > 0 else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let modules = Int(output.extent.width.rounded())
        guard modules >= 21 else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }

        let clearance = 16
        let maxSpan = max(7, modules - clearance)
        var holeHeight = odd(Int((Double(modules) * 0.42).rounded()), limit: maxSpan)
        var holeWidth = odd(Int((CGFloat(holeHeight) * markAspect).rounded()), limit: maxSpan)
        if holeWidth < 7 {
            holeWidth = min(7, maxSpan)
        }
        let fittedHeight = odd(Int((CGFloat(holeWidth) / markAspect).rounded()), limit: maxSpan)
        if fittedHeight < holeHeight {
            holeHeight = fittedHeight
        }

        let module = side / CGFloat(modules)
        let originX = (modules - holeWidth) / 2
        let originY = (modules - holeHeight) / 2
        let hole = CGRect(
            x: CGFloat(originX) * module,
            y: CGFloat(originY) * module,
            width: CGFloat(holeWidth) * module,
            height: CGFloat(holeHeight) * module
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { rendererContext in
            let ctx = rendererContext.cgContext
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            ctx.interpolationQuality = .none
            UIImage(cgImage: cgImage).draw(in: CGRect(x: 0, y: 0, width: side, height: side))

            let center = CGPoint(x: hole.midX, y: hole.midY)
            let radiusX = hole.width / 2
            let radiusY = hole.height / 2
            UIColor.white.setFill()
            for row in originY..<(originY + holeHeight) {
                for col in originX..<(originX + holeWidth) {
                    let rect = CGRect(
                        x: CGFloat(col) * module,
                        y: CGFloat(row) * module,
                        width: module,
                        height: module
                    )
                    if intersectsEllipse(rect, center: center, radiusX: radiusX, radiusY: radiusY) {
                        ctx.fill(rect)
                    }
                }
            }

            let pad = module * 1.15
            let inner = hole.insetBy(dx: pad, dy: pad)
            guard inner.width > 4, inner.height > 4, let logo = UIImage(named: "QRMonogram") else { return }
            logo.draw(in: inner)
        }
    }

    private static func odd(_ value: Int, limit: Int) -> Int {
        var span = min(max(value, 7), limit)
        if span % 2 == 0 {
            span -= 1
        }
        return max(span, 5)
    }

    /// True when the module square touches the oval, so the cleared area has no torn dots.
    private static func intersectsEllipse(
        _ rect: CGRect,
        center: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat
    ) -> Bool {
        guard radiusX > 0, radiusY > 0 else { return false }
        let closestX = min(max(center.x, rect.minX), rect.maxX)
        let closestY = min(max(center.y, rect.minY), rect.maxY)
        let nx = (closestX - center.x) / radiusX
        let ny = (closestY - center.y) / radiusY
        return nx * nx + ny * ny <= 1
    }
}
