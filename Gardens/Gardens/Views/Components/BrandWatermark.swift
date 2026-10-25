import SwiftUI

/// Soft brand mark washed across the screen background (not a corner badge).
struct BrandWatermark: View {
    var opacity: Double = 0.07

    var body: some View {
        GeometryReader { geo in
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: min(geo.size.width, geo.size.height) * 0.72)
                .opacity(opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .rotationEffect(.degrees(-18))
                .offset(y: geo.size.height * 0.06)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Places a faint Gardens logo watermark behind content.
    func gardensBrandWatermark(opacity: Double = 0.07) -> some View {
        background {
            BrandWatermark(opacity: opacity)
        }
    }
}
