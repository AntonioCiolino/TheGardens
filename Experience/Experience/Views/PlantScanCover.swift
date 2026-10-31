import SwiftUI
import GardensCore

/// Camera sheet. A Gardens plant code opens the plant. Anything else stays here with a short error.
struct PlantScanCover: View {
    var onPlant: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var allowed: Bool?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if allowed == true {
                PlantQRScannerView { raw in
                    handle(raw)
                }
                .ignoresSafeArea()
            } else if allowed == false {
                Text("Allow the camera to scan a plant label.")
                    .foregroundStyle(.white)
                    .padding()
            } else {
                ProgressView()
                    .tint(.white)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding()
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .overlay(alignment: .topLeading) {
            Button("Close") { dismiss() }
                .padding()
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
        .task {
            allowed = await CameraPermission.ensureAuthorized()
        }
    }

    private func handle(_ raw: String) {
        do {
            let qr = try CompactPlantQR.decode(raw)
            onPlant(qr.instanceID)
        } catch {
            errorMessage = "That isn't a Gardens plant label."
        }
    }
}
