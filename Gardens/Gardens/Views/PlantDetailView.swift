import SwiftUI
import SwiftData
import GardensCore

struct PlantDetailView: View {
    let instanceID: UUID

    @Environment(\.modelContext) private var modelContext
    @State private var destination: PlantInstanceDestination?
    @State private var qrPayload: String?
    @State private var printError: String?
    @State private var isPrinting = false

    private let qrGenerator = CoreImageQRCodeGenerator()

    var body: some View {
        Group {
            if let destination {
                content(destination)
            } else {
                ProgressView("Loading…")
                    .task { await reload() }
            }
        }
        .navigationTitle(destination?.catalog.name ?? "Plant")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Print", isPresented: Binding(
            get: { printError != nil },
            set: { if !$0 { printError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(printError ?? "")
        }
    }

    @ViewBuilder
    private func content(_ destination: PlantInstanceDestination) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                photo(destination)

                VStack(alignment: .leading, spacing: 8) {
                    Text(destination.catalog.name)
                        .font(.largeTitle.bold())
                    Text(destination.catalog.genus)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    LabeledContent("Vendor", value: destination.instance.vendor)
                    LabeledContent(
                        "Arrived",
                        value: destination.instance.arrivedOn.formatted(date: .long, time: .omitted)
                    )
                }

                careSection(destination)

                qrSection(destination)
            }
            .padding()
        }
        .background { BrandWatermark(opacity: 0.06) }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private func photo(_ destination: PlantInstanceDestination) -> some View {
        if let data = destination.instance.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder
    private func qrSection(_ destination: PlantInstanceDestination) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Label QR")
                .font(.headline)
            Text("Encodes this instance’s ID plus a compact name. Full care history loads from the store by ID.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let qrPayload {
                HStack {
                    Spacer()
                    QRCodeImageView(payload: qrPayload, dimension: 220)
                    Spacer()
                }

                Text(qrPayload)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button {
                    Task { await printLabel(destination: destination, payload: qrPayload) }
                } label: {
                    Label(
                        isPrinting ? "Preparing print…" : "Print label",
                        systemImage: "printer"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPrinting)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func careSection(_ destination: PlantInstanceDestination) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            group(title: "Care", body: destination.careProfile.careInstructions)
            group(title: "Watering check", body: destination.careProfile.wateringCheckGuidance)
            group(title: "Health check", body: destination.careProfile.healthCheckGuidance)

            Text("Care history")
                .font(.headline)
            if destination.careHistory.isEmpty {
                Text("No care events yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(destination.careHistory) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.kind.rawValue.capitalized)
                            .font(.subheadline.weight(.semibold))
                        Text(event.performedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !event.notes.isEmpty {
                            Text(event.notes)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func group(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(body.isEmpty ? "Not set yet." : body)
                .font(.body)
                .foregroundStyle(body.isEmpty ? .secondary : .primary)
        }
    }

    @MainActor
    private func reload() async {
        let repo = SwiftDataPlantRepository(modelContext: modelContext)
        destination = try? await repo.destination(for: instanceID)
        if let destination {
            let detail = PlantInstanceDetail(
                instance: destination.instance,
                catalog: destination.catalog
            )
            qrPayload = try? CompactPlantQR(detail: detail).encodedString()
        }
    }

    @MainActor
    private func printLabel(destination: PlantInstanceDestination, payload: String) async {
        isPrinting = true
        defer { isPrinting = false }
        do {
            let imageData = try qrGenerator.makeQRCodeImageData(from: payload, dimension: 300)
            let printer = UIKitPlantLabelPrinter()
            try await printer.printLabel(
                title: destination.catalog.name,
                subtitle: "\(destination.catalog.genus) · \(destination.instance.vendor)",
                qrImageData: imageData
            )
        } catch {
            printError = error.localizedDescription
        }
    }
}
