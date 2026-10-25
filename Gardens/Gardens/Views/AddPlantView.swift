import SwiftUI
import GardensCore

struct AddPlantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var genus = ""
    @State private var color = ""
    @State private var vendor = ""
    @State private var arrivedOn = Date()
    @State private var photoData: Data?
    @State private var careInstructions = ""
    @State private var wateringCheck = ""
    @State private var healthCheck = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var catalogHint: String?

    private var draft: PlantIntakeDraft {
        PlantIntakeDraft(
            name: name,
            genus: genus,
            color: color,
            vendor: vendor,
            arrivedOn: arrivedOn,
            photoData: photoData,
            careProfile: PlantCareProfile(
                careInstructions: careInstructions,
                wateringCheckGuidance: wateringCheck,
                healthCheckGuidance: healthCheck
            )
        )
    }

    var body: some View {
        Form {
            Section("Photo") {
                PlantPhotoPicker(photoData: $photoData)
            }

            Section("Plant type") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                TextField("Genus", text: $genus)
                    .textInputAutocapitalization(.words)
                TextField("Color", text: $color)
                    .textInputAutocapitalization(.never)
                if let catalogHint {
                    Text(catalogHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("This arrival") {
                DatePicker("Date arrived", selection: $arrivedOn, displayedComponents: .date)
                TextField("Vendor", text: $vendor)
                    .textInputAutocapitalization(.words)
            }

            Section("Care defaults (for new catalog types)") {
                TextField("Care instructions", text: $careInstructions, axis: .vertical)
                TextField("How to check watering", text: $wateringCheck, axis: .vertical)
                TextField("How to check health", text: $healthCheck, axis: .vertical)
            }
        }
        .navigationTitle("New plant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(!draft.isValid || isSaving)
            }
        }
        .onChange(of: name) { _, _ in refreshCatalogHint() }
        .onChange(of: genus) { _, _ in refreshCatalogHint() }
        .alert("Couldn’t save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refreshCatalogHint() {
        let repo = SwiftDataPlantRepository(modelContext: modelContext)
        Task {
            let catalog = (try? await repo.fetchCatalog()) ?? []
            if let match = PlantCatalogMatcher.findExisting(name: name, genus: genus, in: catalog) {
                catalogHint = "Will reuse catalog entry “\(match.name)” (\(match.genus))."
            } else if draft.isValid {
                catalogHint = "Will create a new catalog entry."
            } else {
                catalogHint = nil
            }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let repo = SwiftDataPlantRepository(modelContext: modelContext)
            let service = PlantIntakeService(repository: repo)
            _ = try await service.saveNewArrival(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
