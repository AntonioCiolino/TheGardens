import AVFoundation
import SwiftUI
import GardensCore

/// Live camera QR scan → plant lookup → care logging.
struct ScanPlantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var scannedText = ""
    @State private var destination: PlantInstanceDestination?
    @State private var errorMessage: String?
    @State private var isLookingUp = false
    @State private var showCareLog = false
    @State private var cameraAuthorized = false
    @State private var cameraChecked = false
    @State private var showManualEntry = false
    @State private var statusMessage = "Point at a plant label QR"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraAuthorized {
                PlantQRScannerView { code in
                    Task { await handleScan(code) }
                }
                .ignoresSafeArea()
            } else if cameraChecked {
                cameraDenied
            } else {
                ProgressView("Starting camera…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            VStack {
                scanChrome
                Spacer()
                bottomPanel
            }
        }
        .navigationTitle("Scan plant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Paste") { showManualEntry = true }
            }
        }
        .task {
            cameraAuthorized = await CameraPermission.ensureAuthorized()
            cameraChecked = true
        }
        .sheet(isPresented: $showManualEntry) {
            NavigationStack {
                manualEntryForm
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showCareLog) {
            if let destination {
                NavigationStack {
                    LogCareUpdateView(destination: destination) {
                        dismiss()
                    }
                }
            }
        }
        .alert("Scan", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var scanChrome: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                .frame(width: 240, height: 240)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(0.04))
                )
                .padding(.top, 24)

            Text(statusMessage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.45), in: Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let destination {
                Text(destination.catalog.name)
                    .font(.title3.bold())
                Text(destination.catalog.genus)
                    .foregroundStyle(.secondary)
                Button {
                    showCareLog = true
                } label: {
                    Label("Log care / health update", systemImage: "heart.text.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Camera needs permission to scan plant labels. Use Paste if you’re testing without a printed QR.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private var cameraDenied: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
            Text("Camera access is required to scan plant QR labels.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("Enable Camera for Gardens in Settings → Privacy & Security → Camera.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            Button("Enter code manually") { showManualEntry = true }
                .foregroundStyle(.white)
        }
        .padding(28)
    }

    private var manualEntryForm: some View {
        Form {
            Section {
                TextField("QR contents or UUID", text: $scannedText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .lineLimit(3...8)
            } footer: {
                Text("Paste a compact QR payload or the instance UUID.")
            }
        }
        .navigationTitle("Paste code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showManualEntry = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Find") {
                    showManualEntry = false
                    Task { await handleScan(scannedText) }
                }
                .disabled(scannedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @MainActor
    private func handleScan(_ raw: String) async {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        guard !isLookingUp else { return }

        isLookingUp = true
        statusMessage = "Looking up plant…"
        defer { isLookingUp = false }

        do {
            let repo = SwiftDataPlantRepository(modelContext: modelContext)
            let service = PlantIntakeService(repository: repo)
            let match = try await service.destination(fromScannedQR: code)
            destination = match
            scannedText = code
            statusMessage = "Matched \(match.catalog.name)"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            destination = nil
            statusMessage = "No match — try again"
            errorMessage = "No plant matched that QR. Check the label or paste the code."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
