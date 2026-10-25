import SwiftUI
import GardensCore

/// Resolve a plant by scanning/pasting its QR payload (instance ID or compact JSON),
/// then jump into care logging.
struct ScanPlantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var scannedText = ""
    @State private var destination: PlantInstanceDestination?
    @State private var errorMessage: String?
    @State private var isLookingUp = false
    @State private var showCareLog = false

    var body: some View {
        Form {
            Section {
                Text("Scan a plant label QR, or paste the code / instance ID below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("QR contents or UUID", text: $scannedText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .lineLimit(3...8)
                Button {
                    Task { await lookup() }
                } label: {
                    if isLookingUp {
                        ProgressView()
                    } else {
                        Label("Find plant", systemImage: "qrcode.viewfinder")
                    }
                }
                .disabled(scannedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLookingUp)
            }

            if let destination {
                Section("Matched plant") {
                    Text(destination.catalog.name)
                        .font(.headline)
                    Text(destination.catalog.genus)
                        .foregroundStyle(.secondary)
                    LabeledContent("Vendor", value: destination.instance.vendor)
                    Button {
                        showCareLog = true
                    } label: {
                        Label("Log care / health update", systemImage: "heart.text.clipboard")
                    }
                }
            }
        }
        .navigationTitle("Scan plant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .alert("Not found", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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
    }

    @MainActor
    private func lookup() async {
        isLookingUp = true
        defer { isLookingUp = false }
        destination = nil
        do {
            let repo = SwiftDataPlantRepository(modelContext: modelContext)
            let service = PlantIntakeService(repository: repo)
            destination = try await service.destination(fromScannedQR: scannedText)
        } catch {
            errorMessage = "No plant matched that code. Check the QR or UUID."
        }
    }
}
