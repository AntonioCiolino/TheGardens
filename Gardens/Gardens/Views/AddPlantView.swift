import SwiftUI
import GardensCore

enum AddPlantMode: String, CaseIterable, Identifiable {
    case newType = "New type"
    case existingType = "Existing type"
    var id: String { rawValue }
}

struct AddPlantView: View {
    @EnvironmentObject private var session: GardensSession
    @Environment(\.dismiss) private var dismiss

    /// Called after a successful save with the created batch (for label printing).
    var onSaved: ((PlantArrivalBatch) -> Void)?

    @State private var mode: AddPlantMode = .newType
    @State private var catalog: [PlantCatalogItem] = []
    @State private var selectedCatalogID: UUID?

    @State private var name = ""
    @State private var genus = ""
    @State private var vendor = ""
    @State private var arrivedOn = Date()
    @State private var quantity = 1
    @State private var photoData: Data?
    @State private var photoCredit: String?
    @State private var photoSource: ReferencePhotoSource = .empty
    @State private var photoIsFromCatalog = false
    @State private var autoGenus = ""
    @State private var autoCare = PlantCareProfile.empty
    @State private var lookupTask: Task<Void, Never>?
    @State private var isLookingUp = false
    @State private var lookupNote: String?
    @State private var careInstructions = ""
    @State private var wateringCheck = ""
    @State private var healthCheck = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var catalogHint: String?

    private var selectedCatalog: PlantCatalogItem? {
        catalog.first { $0.id == selectedCatalogID }
    }

    private var draft: PlantIntakeDraft {
        switch mode {
        case .newType:
            return PlantIntakeDraft(
                catalogMode: .newOrMatchType,
                name: name,
                genus: genus,
                vendor: vendor,
                arrivedOn: arrivedOn,
                photoData: photoData,
                photoCredit: photoCredit,
                careProfile: PlantCareProfile(
                    careInstructions: careInstructions,
                    wateringCheckGuidance: wateringCheck,
                    healthCheckGuidance: healthCheck
                ),
                quantity: quantity
            )
        case .existingType:
            return PlantIntakeDraft(
                catalogMode: .existingType(catalogItemID: selectedCatalogID ?? UUID()),
                name: selectedCatalog?.name ?? "",
                genus: selectedCatalog?.genus ?? "",
                vendor: vendor,
                arrivedOn: arrivedOn,
                photoData: photoData,
                photoCredit: photoCredit,
                quantity: quantity
            )
        }
    }

    private var canSave: Bool {
        guard !isSaving, quantity >= 1 else { return false }
        switch mode {
        case .newType:
            return draft.isValid
        case .existingType:
            return selectedCatalogID != nil && draft.isValid
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Arrival", selection: $mode) {
                    ForEach(AddPlantMode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(
                    mode == .newType
                        ? "First time this plant type arrives — enter the type once, then set how many physical plants came in."
                        : "You already carry this type — pick it and add another shipment. Each plant still gets its own QR."
                )
            }

            if mode == .newType {
                Section("Plant type") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Genus", text: $genus)
                        .textInputAutocapitalization(.words)
                    if let catalogHint {
                        Text(catalogHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Plant type") {
                    if catalog.isEmpty {
                        Text("No catalog types yet. Add a new type first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Catalog plant", selection: $selectedCatalogID) {
                            Text("Select…").tag(UUID?.none)
                            ForEach(catalog) { item in
                                Text("\(item.name) · \(item.genus)").tag(Optional(item.id))
                            }
                        }
                    }
                }
            }

            Section {
                if mode == .existingType, photoIsFromCatalog, photoData != nil {
                    catalogPhotoPreview
                    Text("Using the photo already on file for this plant type. You can replace it if this shipment looks different.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    PlantPhotoPicker(photoData: userPhoto, replaceOnly: true)
                } else {
                    if photoData != nil {
                        catalogPhotoPreview
                    }
                    if let photoCredit, photoSource == .reference {
                        Text(photoCredit)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    PlantPhotoPicker(photoData: userPhoto, replaceOnly: photoData != nil)
                }
                Button {
                    lookupTask?.cancel()
                    Task { await lookupReference(forcePhoto: true) }
                } label: {
                    HStack {
                        Label("Get reference photo", systemImage: "photo.badge.plus")
                        if isLookingUp {
                            ProgressView()
                        }
                    }
                }
                .disabled(isLookingUp || !canLookupReference)
                if isLookingUp {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking up the plant…")
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("Photo")
            } footer: {
                Text("A photo you take is the Gardens photo. Get reference photo fills a Wikipedia picture when you don’t have one yet.")
            }

            Section("This arrival") {
                Stepper(value: $quantity, in: 1...500) {
                    Text("Quantity: \(quantity)")
                }
                Text("Creates \(quantity) unique plant record\(quantity == 1 ? "" : "s") and QR label\(quantity == 1 ? "" : "s").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                DatePicker("Date arrived", selection: $arrivedOn, displayedComponents: .date)
                TextField("Vendor", text: $vendor)
                    .textInputAutocapitalization(.words)
            }

            if mode == .newType {
                Section {
                    TextField("Care instructions", text: $careInstructions, axis: .vertical)
                    TextField("How to check watering", text: $wateringCheck, axis: .vertical)
                    TextField("How to check health", text: $healthCheck, axis: .vertical)
                } header: {
                    Text("Care defaults (for new catalog types)")
                } footer: {
                    Text(lookupNote ?? "Type a common name or a genus. Gardens fills these as suggestions you can edit.")
                }
            }
        }
        .overlay {
            if isSaving {
                savingOverlay("Saving plant…")
            }
        }
        .navigationTitle(mode == .newType ? "New arrival" : "Add more")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(quantity > 1 ? "Save \(quantity)" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .task { await loadCatalog() }
        .onChange(of: mode) { _, newMode in
            if newMode == .existingType {
                if selectedCatalogID == nil {
                    selectedCatalogID = catalog.first?.id
                }
                Task { await loadReferencePhoto() }
            } else {
                lookupTask?.cancel()
                if photoIsFromCatalog || photoSource == .catalog {
                    photoData = nil
                    photoCredit = nil
                    photoSource = .empty
                    photoIsFromCatalog = false
                }
            }
        }
        .onChange(of: selectedCatalogID) { _, _ in
            Task { await loadReferencePhoto() }
        }
        .onChange(of: photoData) { _, newValue in
            // User replaced the catalog photo manually.
            if photoIsFromCatalog, newValue != nil {
                // keep flag until they clear — still fine to save
            }
            if newValue == nil {
                photoIsFromCatalog = false
            }
        }
        .onChange(of: name) { _, _ in
            refreshCatalogHint()
            scheduleLookup()
        }
        .onChange(of: genus) { _, _ in
            refreshCatalogHint()
            scheduleLookup()
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
    private var catalogPhotoPreview: some View {
        if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @MainActor
    private func loadCatalog() async {
        catalog = (try? await session.repository.fetchCatalog()) ?? []
        if mode == .existingType, selectedCatalogID == nil {
            selectedCatalogID = catalog.first?.id
        }
        if catalog.isEmpty {
            mode = .newType
        } else if mode == .existingType {
            await loadReferencePhoto()
        }
    }

    @MainActor
    private func loadReferencePhoto() async {
        guard mode == .existingType, let id = selectedCatalogID else { return }
        if let data = try? await session.repository.referencePhoto(for: id) {
            photoData = data
            photoCredit = nil
            photoSource = .catalog
            photoIsFromCatalog = true
        } else {
            photoData = nil
            photoCredit = nil
            photoSource = .empty
            photoIsFromCatalog = false
        }
    }

    private func refreshCatalogHint() {
        guard mode == .newType else {
            catalogHint = nil
            return
        }
        Task {
            if let match = PlantCatalogMatcher.findExisting(name: name, genus: genus, in: catalog) {
                catalogHint = "Name/genus already in catalog — will reuse “\(match.name)” and add \(quantity) new instance\(quantity == 1 ? "" : "s")."
            } else if draft.isValid {
                catalogHint = "Will create a new catalog type and \(quantity) instance\(quantity == 1 ? "" : "s")."
            } else {
                catalogHint = nil
            }
        }
    }

    private var userPhoto: Binding<Data?> {
        Binding(
            get: { photoData },
            set: { newValue in
                photoData = newValue
                photoIsFromCatalog = false
                if newValue == nil {
                    photoSource = .empty
                    photoCredit = nil
                } else {
                    photoSource = .user
                    photoCredit = nil
                }
            }
        )
    }

    private var canLookupReference: Bool {
        switch mode {
        case .newType:
            return name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
                || genus.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        case .existingType:
            return selectedCatalog != nil
        }
    }

    private func scheduleLookup() {
        lookupTask?.cancel()
        guard mode == .newType else { return }
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await lookupReference(forcePhoto: false)
        }
    }

    @MainActor
    private func lookupReference(forcePhoto: Bool) async {
        let lookupName: String
        let lookupGenus: String
        switch mode {
        case .newType:
            lookupName = name
            lookupGenus = genus
        case .existingType:
            lookupName = selectedCatalog?.name ?? ""
            lookupGenus = selectedCatalog?.genus ?? ""
        }
        guard lookupName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            || lookupGenus.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        else { return }

        isLookingUp = true
        defer { isLookingUp = false }
        do {
            let suggestion = try await PlantReferenceLoader.load(name: lookupName, genus: lookupGenus)
            guard !Task.isCancelled else { return }
            if mode == .newType {
                applyTextSuggestions(suggestion)
            }
            let mayReplacePhoto = forcePhoto || photoSource == .empty || photoSource == .reference
            if mayReplacePhoto, let data = suggestion.photoData {
                photoCredit = suggestion.photoCredit
                photoSource = .reference
                photoIsFromCatalog = false
                photoData = data
            } else if suggestion.photoData == nil {
                lookupNote = "No reference photo for that name. \(suggestion.careNote)"
            }
        } catch {
            lookupNote = error.localizedDescription
        }
    }

    private func applyTextSuggestions(_ suggestion: PlantReferenceSuggestion) {
        if genus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || genus == autoGenus {
            genus = suggestion.scientificName
            autoGenus = suggestion.scientificName
        }
        if careInstructions.isEmpty || careInstructions == autoCare.careInstructions {
            careInstructions = suggestion.careProfile.careInstructions
        }
        if wateringCheck.isEmpty || wateringCheck == autoCare.wateringCheckGuidance {
            wateringCheck = suggestion.careProfile.wateringCheckGuidance
        }
        if healthCheck.isEmpty || healthCheck == autoCare.healthCheckGuidance {
            healthCheck = suggestion.careProfile.healthCheckGuidance
        }
        autoCare = PlantCareProfile(
            careInstructions: careInstructions,
            wateringCheckGuidance: wateringCheck,
            healthCheckGuidance: healthCheck
        )
        lookupNote = suggestion.careNote
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let service = PlantIntakeService(repository: session.repository)
            let batch = try await service.saveNewArrival(draft)
            onSaved?(batch)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private func savingOverlay(_ title: String) -> some View {
    ZStack {
        Color.black.opacity(0.2).ignoresSafeArea()
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.headline)
        }
        .padding(24)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum ReferencePhotoSource {
    case empty
    case user
    case reference
    case catalog
}
