import SwiftUI
import GardensCore

/// Shows every unique QR from an arrival so the user can print the full set
/// (e.g. seven labels for seven plants of the same type).
struct BatchLabelPrintView: View {
    let batch: PlantArrivalBatch
    @Environment(\.dismiss) private var dismiss

    @State private var payloads: [(PlantInstanceDetail, String)] = []
    @State private var printRequest: LabelPrintRequest?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    Button {
                        printRequest = LabelPrintRequest(jobs: jobs)
                    } label: {
                        Label(
                            "Print \(batch.count) label\(batch.count == 1 ? "" : "s")",
                            systemImage: "printer"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(payloads.isEmpty)

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
                                printRequest = LabelPrintRequest(jobs: [
                                    PlantLabelJob(
                                        id: detail.instance.id,
                                        title: detail.catalog.name,
                                        subtitle: detail.catalog.genus,
                                        qrPayload: payload
                                    )
                                ])
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
            .sheet(item: $printRequest) { request in
                LabelPrinterSheet(jobs: request.jobs)
            }
        }
    }

    private var jobs: [PlantLabelJob] {
        payloads.map { detail, payload in
            PlantLabelJob(
                id: detail.instance.id,
                title: detail.catalog.name,
                subtitle: detail.catalog.genus,
                qrPayload: payload
            )
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

}
