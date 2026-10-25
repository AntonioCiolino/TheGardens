import SwiftUI
import GardensCore

struct PlantDetailView: View {
    let instanceID: UUID
    var autoOpenCareLog: Bool = false

    @EnvironmentObject private var session: GardensSession
    @State private var destination: PlantInstanceDestination?
    @State private var qrPayload: String?
    @State private var printError: String?
    @State private var isPrinting = false
    @State private var showingCareLog = false

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
        .toolbar {
            if destination != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCareLog = true
                    } label: {
                        Label("Log care", systemImage: "heart.text.clipboard")
                    }
                }
            }
        }
        .task(id: destination?.id) {
            if autoOpenCareLog, destination != nil {
                showingCareLog = true
            }
        }
        .sheet(isPresented: $showingCareLog) {
            if let destination {
                NavigationStack {
                    LogCareUpdateView(destination: destination) {
                        Task { await reload() }
                    }
                }
            }
        }
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
        .background { BrandWatermark(opacity: 0.14) }
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
            Text("Deep link starts with gardens:// so Camera can open Gardens. Full care history loads from the store by ID.")
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.kind.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(event.performedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !event.wateringObservation.isEmpty {
                            Text("Watering: \(event.wateringObservation)")
                                .font(.caption)
                        }
                        if !event.healthObservation.isEmpty {
                            Text("Health: \(event.healthObservation)")
                                .font(.caption)
                        }
                        if !event.notes.isEmpty {
                            Text(event.notes)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                showingCareLog = true
            } label: {
                Label("Log care / health update", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
        destination = try? await session.repository.destination(for: instanceID)
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
