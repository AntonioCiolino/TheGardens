import SwiftUI
import UIKit

/// Brand green used by the launch splash and Jen’s note.
let GardensSplashGreen = Color(red: 0.180, green: 0.520, blue: 0.290)

/// Launch splash. Covers the whole screen, including the status bar and home indicator.
struct SplashView: View {
    /// Set when the phone is already inside a garden fence. Nil hides the greeting.
    var placeName: String?

    var body: some View {
        ZStack {
            background
            BotanicalCorners()

            VStack(spacing: 22) {
                Image("QRMonogram")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 340)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 28)
                    .background {
                        Capsule()
                            .fill(Color(red: 0.94, green: 0.93, blue: 0.88))
                    }
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                    .accessibilityHidden(true)

                Text("The Gardens Experience")
                    .font(.subheadline.weight(.medium))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.7))

                if let placeName {
                    VStack(spacing: 10) {
                        GrowingCaption(
                            text: "We're glad you're here",
                            font: .title3.weight(.semibold),
                            delay: 0.15
                        )
                        GrowingCaption(
                            text: placeName,
                            font: .footnote.weight(.medium),
                            delay: 0.55
                        )
                    }
                    .padding(.top, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("We're glad you're here. \(placeName)")
                }
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .accessibilityLabel("The Gardens Experience")
    }

    private var background: some View {
        GardensSplashGreen.ignoresSafeArea()
    }
}

/// Corner engravings that grow and fade in once, then hold.
struct BotanicalCorners: View {
    @State private var vinesGrown = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.78
            ZStack {
                corner(side: side, xSign: 1, ySign: 1, anchor: .topLeading, alignment: .topLeading)
                corner(side: side, xSign: -1, ySign: 1, anchor: .topTrailing, alignment: .topTrailing)
                corner(side: side, xSign: 1, ySign: -1, anchor: .bottomLeading, alignment: .bottomLeading)
                corner(side: side, xSign: -1, ySign: -1, anchor: .bottomTrailing, alignment: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 5)) {
                vinesGrown = true
            }
        }
    }

    private func corner(
        side: CGFloat,
        xSign: CGFloat,
        ySign: CGFloat,
        anchor: UnitPoint,
        alignment: Alignment
    ) -> some View {
        let grown: CGFloat = vinesGrown ? 1 : 0.86
        return vinePlate
            .frame(width: side, height: side)
            .scaleEffect(x: xSign, y: ySign, anchor: .center)
            .scaleEffect(grown, anchor: anchor)
            .opacity(vinesGrown ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var vinePlate: some View {
        Image(uiImage: VinePlate.image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }
}

/// Grows once from small to full size, then holds. It does not pulse back.
struct GrowingCaption: View {
    var text: String
    var font: Font
    var delay: Double
    /// Wider card for a paragraph. Short lines stay in a capsule.
    var roomy = false
    @State private var grown = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, roomy ? 22 : 16)
            .padding(.vertical, roomy ? 18 : 8)
            .frame(maxWidth: roomy ? .infinity : nil)
            .background {
                if roomy {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                }
            }
            .scaleEffect(grown ? 1 : 0.72)
            .opacity(grown ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 1.25).delay(delay)) {
                    grown = true
                }
            }
    }
}

/// Lifts the cream engraving off the plate’s green so it sits on the splash color.
private enum VinePlate {
    static let image: UIImage = knockedOutGreen(UIImage(named: "SplashVineCorner"))

    private static func knockedOutGreen(_ source: UIImage?) -> UIImage {
        guard let source, let cgImage = source.cgImage else {
            return UIImage()
        }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return source }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Float(pixels[index]) / 255
            let green = Float(pixels[index + 1]) / 255
            let blue = Float(pixels[index + 2]) / 255
            let brightness = (red + green + blue) / 3
            let greenCast = green - max(red, blue)
            let ink = max(0, min(1, (brightness - 0.42) / 0.38))
            let alpha = greenCast > 0.08 && brightness < 0.62 ? Float(0) : ink
            pixels[index] = UInt8(red * alpha * 255)
            pixels[index + 1] = UInt8(green * alpha * 255)
            pixels[index + 2] = UInt8(blue * alpha * 255)
            pixels[index + 3] = UInt8(alpha * 255)
        }
        guard let out = context.makeImage() else { return source }
        return UIImage(cgImage: out, scale: source.scale, orientation: source.imageOrientation)
    }
}
