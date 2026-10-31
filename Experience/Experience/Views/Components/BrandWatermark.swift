import SwiftUI

/// The intake brand mark, copied into this catalog. Not a new drawing.
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

struct BrandLogo: View {
    var height: CGFloat = 88

    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("The Gardens")
    }
}
