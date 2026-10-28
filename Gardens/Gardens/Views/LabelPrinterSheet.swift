import SwiftUI
import GardensCore

struct LabelPrinterSheet: View {
    let jobs: [PlantLabelJob]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var printer = T50BluetoothPrinter()
    @State private var errorMessage: String?

    private let qrGenerator = CoreImageQRCodeGenerator()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Turn the T50M on and hold it near this iPhone. Quit the Katasymbol app first — the printer stays connected to only one app. Gardens lists that printer, not every Bluetooth device nearby.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if printer.discovered.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(printer.statusText)
                                .font(.subheadline)
                        }
                    } else {
                        ForEach(printer.discovered) { item in
                            Button {
                                printer.connect(item)
                            } label: {
                                HStack {
                                    Label(item.name, systemImage: "printer")
                                    Spacer()
                                    if printer.connectedIdentifier == item.identifier {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                            }
                            .disabled(printer.isBusy)
                        }
                    }
                } header: {
                    Text("Nearby printers")
                } footer: {
                    if !printer.discovered.isEmpty && printer.connectedName == nil {
                        Text(printer.statusText)
                    }
                }

                if printer.connectedName != nil {
                    Section {
                        Button {
                            Task { await printOnPrinter() }
                        } label: {
                            HStack {
                                Label(printTitle, systemImage: "printer.fill")
                                Spacer()
                                if printer.isBusy {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(printer.isBusy)
                    } footer: {
                        Text(printer.statusText)
                    }
                }

                Section {
                    Button("AirPrint instead") {
                        Task { await printWithAirPrint() }
                    }
                    .disabled(printer.isBusy)
                }
            }
            .navigationTitle(jobs.count == 1 ? "Print label" : "Print labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        printer.stop()
                        dismiss()
                    }
                }
            }
            .alert("Print", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { printer.start() }
        }
    }

    private var printTitle: String {
        jobs.count == 1 ? "Print this label" : "Print \(jobs.count) labels"
    }

    @MainActor
    private func printOnPrinter() async {
        do {
            try await printer.printJobs(jobs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func printWithAirPrint() async {
        do {
            var images: [Data] = []
            for job in jobs {
                images.append(try qrGenerator.makeQRCodeImageData(from: job.qrPayload, dimension: 280))
            }
            let air = UIKitPlantLabelPrinter()
            try await air.printLabels(
                title: jobs.first?.title ?? "Gardens",
                subtitle: jobs.first?.subtitle ?? "",
                qrImageDataList: images
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
