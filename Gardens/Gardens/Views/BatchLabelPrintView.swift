import SwiftUI
import GardensCore

/// Shows every unique QR from an arrival so the user can print the full set
/// (e.g. seven labels for seven plants of the same type).
struct BatchLabelPrintView: View {
    let batch: PlantArrivalBatch
    @Environment(\.dismiss) private var dismiss

    @State private var payloads: [(PlantInstanceDetail, String)] = []
    @State private var isPrinting = false
    @State private var printError: String?
    @State private var printMessage: String?

    private let qrGenerator = CoreImageQRCodeGenerator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    Button {
                        Task { await printAll() }
                    } label: {
                        Label(
                            isPrinting
                                ? "Preparing…"
                                : "Print \(batch.count) label\(batch.count == 1 ? "" : "s")",
                            systemImage: "printer"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPrinting || payloads.isEmpty)

                    if let printMessage {
                        Text(printMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(payloads.enumerated()), id: \.element.0.id) { index, pair in
                        let (detail, payload) = pair
                        VStack(spacing: 10) {
                            Text("\(batch.catalog.name) · #\(index + 1) of \(batch.count)")
                                .font(.subheadline.weight(.semibold))
                            Text(detail.instance.id.uuidString)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            QRCodeImageView(payload: payload, dimension: 180)
                            Button("Print this label") {
                                Task { await printOne(detail: detail, payload: payload) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .navigationTitle("Print labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { loadPayloads() }
            .alert("Print", isPresented: Binding(
                get: { printError != nil },
                set: { if !$0 { printError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(printError ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(batch.catalog.name)
                .font(.title2.bold())
            Text(batch.catalog.genus)
                .foregroundStyle(.secondary)
            Text("\(batch.count) unique plant\(batch.count == 1 ? "" : "s") — each QR is a different instance ID.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func loadPayloads() {
        payloads = batch.instances.compactMap { detail in
            guard let payload = try? CompactPlantQR(detail: detail).encodedString() else {
                return nil
            }
            return (detail, payload)
        }
    }

    @MainActor
    private func printAll() async {
        isPrinting = true
        defer { isPrinting = false }
        do {
            var images: [Data] = []
            for (_, payload) in payloads {
                images.append(try qrGenerator.makeQRCodeImageData(from: payload, dimension: 280))
            }
            let printer = UIKitPlantLabelPrinter()
            try await printer.printLabels(
                title: batch.catalog.name,
                subtitle: "\(batch.catalog.genus) · \(batch.count) labels",
                qrImageDataList: images
            )
            printMessage = "Print sheet opened for \(batch.count) label\(batch.count == 1 ? "" : "s")."
        } catch {
            printError = error.localizedDescription
        }
    }

    @MainActor
    private func printOne(detail: PlantInstanceDetail, payload: String) async {
        do {
            let image = try qrGenerator.makeQRCodeImageData(from: payload, dimension: 300)
            let printer = UIKitPlantLabelPrinter()
            try await printer.printLabel(
                title: detail.catalog.name,
                subtitle: "\(detail.catalog.genus) · \(detail.instance.vendor)",
                qrImageData: image
            )
        } catch {
            printError = error.localizedDescription
        }
    }
}
