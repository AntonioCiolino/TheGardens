import SwiftUI
import GardensCore

struct PlantDetailView: View {
    let instanceID: UUID
    var autoOpenCareLog: Bool = false

    @EnvironmentObject private var session: GardensSession
    @State private var destination: PlantInstanceDestination?
    @State private var qrPayload: String?
    @State private var printRequest: LabelPrintRequest?
    @State private var showingCareLog = false
    @State private var showingPhotoEditor = false

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
        .sheet(isPresented: $showingPhotoEditor) {
            if let destination {
                EditPlantPhotoSheet(
                    instanceID: destination.instance.id,
                    plantName: destination.catalog.name,
                    genus: destination.catalog.genus,
                    initialPhoto: destination.instance.photoData,
                    initialCredit: destination.instance.photoCredit
                ) {
                    Task { await reload() }
                }
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
        .sheet(item: $printRequest) { request in
            LabelPrinterSheet(jobs: request.jobs)
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
        VStack(alignment: .leading, spacing: 12) {
            if let data = destination.instance.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                if let credit = destination.instance.photoCredit, !credit.isEmpty {
                    Text(credit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "camera")
                                .font(.title)
                            Text("No photo yet")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
            }

            Button {
                showingPhotoEditor = true
            } label: {
                Label(
                    destination.instance.photoData == nil ? "Add photo" : "Update photo",
                    systemImage: "camera"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
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
                    printRequest = LabelPrintRequest(jobs: [
                        PlantLabelJob(
                            id: destination.instance.id,
                            title: destination.catalog.name,
                            subtitle: destination.catalog.genus,
                            qrPayload: qrPayload
                        )
                    ])
                } label: {
                    Label("Print label", systemImage: "printer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        if let loaded = try? await session.repository.destination(for: instanceID) {
            destination = loaded
        }
        if let destination {
            let detail = PlantInstanceDetail(
                instance: destination.instance,
                catalog: destination.catalog
            )
            qrPayload = try? CompactPlantQR(detail: detail).encodedString()
        }
    }

}

/// Replace the photo on a plant that already exists. The chosen image is shown here before it is saved.
private struct EditPlantPhotoSheet: View {
    let instanceID: UUID
    let plantName: String
    let genus: String
    let initialPhoto: Data?
    let initialCredit: String?
    var onSaved: () -> Void

    @EnvironmentObject private var session: GardensSession
    @Environment(\.dismiss) private var dismiss

    @State private var photoData: Data?
    @State private var baseline: Data?
    @State private var pendingCredit: String?
    @State private var isSaving = false
    @State private var isLookingUp = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    if let pendingCredit, !pendingCredit.isEmpty {
                        Text(pendingCredit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    PlantPhotoPicker(photoData: userPhoto, replaceOnly: photoData != nil)
                    Button {
                        Task { await loadReference() }
                    } label: {
                        HStack {
                            Label("Get reference photo", systemImage: "photo.badge.plus")
                            if isLookingUp {
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLookingUp || isSaving)

                    if isLookingUp {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking up the plant…")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if isSaving {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Saving photo…")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle("Edit \(plantName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                baseline = initialPhoto
                pendingCredit = initialCredit
                photoData = initialPhoto
            }
            .onChange(of: photoData) { _, newValue in
                guard newValue != baseline else { return }
                Task { await persist(newValue, credit: pendingCredit) }
            }
            .alert("Couldn’t save photo", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var userPhoto: Binding<Data?> {
        Binding(
            get: { photoData },
            set: { newValue in
                pendingCredit = nil
                photoData = newValue
            }
        )
    }

    @MainActor
    private func loadReference() async {
        isLookingUp = true
        defer { isLookingUp = false }
        do {
            let suggestion = try await PlantReferenceLoader.load(name: plantName, genus: genus)
            guard let data = suggestion.photoData else {
                errorMessage = "No reference photo for \(plantName)."
                return
            }
            pendingCredit = suggestion.photoCredit
            photoData = data
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func persist(_ data: Data?, credit: String?) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.updatePlantPhoto(instanceID: instanceID, photoData: data, photoCredit: credit)
            baseline = data
            onSaved()
        } catch {
            photoData = baseline
            pendingCredit = initialCredit
            errorMessage = error.localizedDescription
        }
    }
}
