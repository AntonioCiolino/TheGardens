import SwiftUI
import GardensCore

struct QRCodeImageView: View {
    let payload: String
    var dimension: CGFloat = 200

    private let generator = CoreImageQRCodeGenerator()

    var body: some View {
        Group {
            if let data = try? generator.makeQRCodeImageData(
                from: payload,
                dimension: Int(dimension)
            ),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: dimension, height: dimension)
                    .accessibilityLabel("Plant QR code")
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.secondary, style: StrokeStyle(dash: [4]))
                    .frame(width: dimension, height: dimension)
                    .overlay {
                        Text("QR unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
}
