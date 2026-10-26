import SwiftUI
import GardensCore

/// Log maintenance / watering / health after scanning (or opening) a plant instance.
struct LogCareUpdateView: View {
    let destination: PlantInstanceDestination
    var onSaved: (() -> Void)?

    @EnvironmentObject private var session: GardensSession
    @Environment(\.dismiss) private var dismiss

    @State private var kind: CareEventKind = .healthCheck
    @State private var wateringObservation = ""
    @State private var healthObservation = ""
    @State private var notes = ""
    @State private var performedAt = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var draft: CareUpdateDraft {
        CareUpdateDraft(
            instanceID: destination.instance.id,
            kind: kind,
            performedAt: performedAt,
            wateringObservation: wateringObservation,
            healthObservation: healthObservation,
            notes: notes
        )
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Plant", value: destination.catalog.name)
                LabeledContent("Genus", value: destination.catalog.genus)
                Text(destination.instance.id.uuidString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Section("Guidance on file") {
                guidanceRow("Care", destination.careProfile.careInstructions)
                guidanceRow("Watering check", destination.careProfile.wateringCheckGuidance)
                guidanceRow("Health check", destination.careProfile.healthCheckGuidance)
            }

            Section("What did you just do?") {
                Picker("Maintenance", selection: $kind) {
                    ForEach(CareEventKind.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                DatePicker("When", selection: $performedAt)
            }

            Section("Watering") {
                Text(destination.careProfile.wateringCheckGuidance.isEmpty
                     ? "Record what you observed about watering."
                     : destination.careProfile.wateringCheckGuidance)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Watering observation", text: $wateringObservation, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Health") {
                Text(destination.careProfile.healthCheckGuidance.isEmpty
                     ? "Record pests, leaf color, overall condition, etc."
                     : destination.careProfile.healthCheckGuidance)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Health observation", text: $healthObservation, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Notes") {
                TextField("Anything else about this visit", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Saving care note…")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .navigationTitle("Log care")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .alert("Couldn’t save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func guidanceRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(body.isEmpty ? "Not set yet." : body)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let service = PlantIntakeService(repository: session.repository)
            _ = try await service.logCareUpdate(draft)
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
