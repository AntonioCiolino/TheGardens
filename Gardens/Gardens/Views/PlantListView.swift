import SwiftUI
import UIKit
import GardensCore

struct PlantListView: View {
    @Binding var deepLinkPlantID: UUID?
    @Binding var openCareFromDeepLink: Bool

    @EnvironmentObject private var session: GardensSession

    @State private var showingAdd = false
    @State private var showingScan = false
    @State private var showingSync = false
    @State private var showingProfile = false
    @State private var sortMode: PlantSortMode = .recent
    @State private var batchToPrint: PlantArrivalBatch?
    @State private var path = NavigationPath()
    @State private var pendingDelete: PlantInstanceDetail?
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                BrandWatermark(opacity: 0.16)

                List {
                    if session.isLoadingInventory && session.instances.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Loading plants from iCloud…")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 420)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else if session.instances.isEmpty {
                        ContentUnavailableView(
                            "No plants yet",
                            systemImage: "leaf",
                            description: Text(emptyDescription)
                        )
                        .frame(maxWidth: .infinity, minHeight: 420)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        sortControlSection
                        plantSections
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await session.refresh()
                }
            }
            .navigationTitle("Gardens")
            .navigationDestination(for: UUID.self) { id in
                PlantDetailView(
                    instanceID: id,
                    autoOpenCareLog: openCareFromDeepLink && deepLinkPlantID == id
                )
                .onAppear {
                    if openCareFromDeepLink, deepLinkPlantID == id {
                        openCareFromDeepLink = false
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingScan = true
                    } label: {
                        Label("Scan", systemImage: "qrcode.viewfinder")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSync = true
                    } label: {
                        Label(
                            session.usesSharedCloud ? "Synced" : "Sync",
                            systemImage: session.usesSharedCloud
                                ? "checkmark.icloud"
                                : "icloud.and.arrow.up"
                        )
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingProfile = true
                    } label: {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Plant", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let note = session.errorMessage ?? (session.instances.isEmpty ? nil : session.statusMessage) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(.systemBackground))
                }
            }
            .sheet(isPresented: $showingAdd) {
                NavigationStack {
                    AddPlantView { batch in
                        batchToPrint = batch
                        Task { await session.refresh() }
                    }
                }
            }
            .sheet(isPresented: $showingScan) {
                NavigationStack {
                    ScanPlantView { plantID in
                        showingScan = false
                        Task { @MainActor in
                            await Task.yield()
                            path.append(plantID)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSync) {
                NavigationStack {
                    SignInView()
                }
            }
            .sheet(isPresented: $showingProfile) {
                NavigationStack {
                    ProfileView()
                }
            }
            .sheet(item: $batchToPrint) { batch in
                BatchLabelPrintView(batch: batch)
            }
            .onChange(of: deepLinkPlantID) { _, newID in
                guard let newID else { return }
                path.append(newID)
            }
            .confirmationDialog(
                "Delete this plant?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete \(pendingDelete?.catalog.name ?? "plant")", role: .destructive) {
                    let detail = pendingDelete
                    pendingDelete = nil
                    if let detail {
                        Task { await delete(detail) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            } message: {
                Text("This deletes the plant and its care notes from iCloud. If it is the last plant of this type, the type is deleted too.")
            }
            .overlay {
                if isDeleting {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Deleting plant…")
                                .font(.headline)
                        }
                        .padding(24)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .alert("Couldn’t delete", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    @ViewBuilder
    private var sortControlSection: some View {
        Section {
            Picker("Sort", selection: $sortMode) {
                ForEach(PlantSortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }

    @ViewBuilder
    private var plantSections: some View {
        ForEach(groupedSections) { group in
            if group.title.isEmpty {
                Section {
                    ForEach(group.items) { detail in
                        plantRow(for: detail)
                    }
                }
            } else {
                Section(group.title) {
                    ForEach(group.items) { detail in
                        plantRow(for: detail)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func plantRow(for detail: PlantInstanceDetail) -> some View {
        NavigationLink(value: detail.instance.id) {
            PlantRowView(detail: detail)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            deleteSwipe(for: detail)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            deleteSwipe(for: detail)
        }
        .listRowBackground(Color(.secondarySystemGroupedBackground))
    }

    private func deleteSwipe(for detail: PlantInstanceDetail) -> some View {
        Button(role: .destructive) {
            pendingDelete = detail
            showingDeleteConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @MainActor
    private func delete(_ detail: PlantInstanceDetail) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await session.deletePlant(instanceID: detail.instance.id)
            if path.count > 0 {
                path = NavigationPath()
            }
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private var emptyDescription: String {
        if let error = session.errorMessage {
            return error
        }
        if session.user == nil {
            return "Connect iCloud under Sync to share inventory with your team, or add a plant to keep it on this device for now."
        }
        return "Log an arrival — one plant or a whole carton."
    }

    /// Sorts (and for some modes, groups) the current inventory for display.
    private var groupedSections: [PlantGroup] {
        let items = session.instances
        switch sortMode {
        case .recent:
            // Newest arrivals first. Many plants share one arrival date, so a stable
            // name → id tiebreaker keeps tied rows from reshuffling on each refresh.
            let sorted = items.sorted { lhs, rhs in
                if lhs.instance.arrivedOn != rhs.instance.arrivedOn {
                    return lhs.instance.arrivedOn > rhs.instance.arrivedOn
                }
                return Self.stableBefore(lhs, rhs)
            }
            return [PlantGroup(id: "recent", title: "", items: sorted)]

        case .alphabetical:
            let sorted = items.sorted { lhs, rhs in Self.stableBefore(lhs, rhs) }
            return [PlantGroup(id: "alpha", title: "", items: sorted)]

        case .genus:
            let grouped = Dictionary(grouping: items) { detail -> String in
                let genus = detail.catalog.genus.trimmingCharacters(in: .whitespacesAndNewlines)
                return genus.isEmpty ? "Unknown genus" : genus
            }
            return grouped.keys
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { key in
                    let sorted = grouped[key, default: []].sorted { lhs, rhs in Self.stableBefore(lhs, rhs) }
                    return PlantGroup(id: key, title: key, items: sorted)
                }

        case .needsCare:
            // Most overdue first: rank by last care date (or arrival date if never cared for).
            // A name + id tiebreaker keeps equal/undated plants in a stable order instead of
            // shuffling on each refresh.
            let sorted = items.sorted { lhs, rhs in
                if lhs.attentionDate != rhs.attentionDate {
                    return lhs.attentionDate < rhs.attentionDate
                }
                let names = lhs.catalog.name.localizedCaseInsensitiveCompare(rhs.catalog.name)
                if names != .orderedSame {
                    return names == .orderedAscending
                }
                return lhs.instance.id.uuidString < rhs.instance.id.uuidString
            }
            return [PlantGroup(id: "needsCare", title: "", items: sorted)]
        }
    }

    /// Deterministic ordering for rows whose primary sort key is equal: name, then genus,
    /// then the stable instance id. Prevents tied rows from reshuffling between refreshes.
    private static func stableBefore(_ lhs: PlantInstanceDetail, _ rhs: PlantInstanceDetail) -> Bool {
        let names = lhs.catalog.name.localizedCaseInsensitiveCompare(rhs.catalog.name)
        if names != .orderedSame {
            return names == .orderedAscending
        }
        let genera = lhs.catalog.genus.localizedCaseInsensitiveCompare(rhs.catalog.genus)
        if genera != .orderedSame {
            return genera == .orderedAscending
        }
        return lhs.instance.id.uuidString < rhs.instance.id.uuidString
    }
}

/// How the plant list is ordered (and for genus, grouped).
enum PlantSortMode: String, CaseIterable, Identifiable {
    case needsCare
    case recent
    case genus
    case alphabetical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recent"
        case .alphabetical: return "A–Z"
        case .genus: return "Genus"
        case .needsCare: return "Needs care"
        }
    }
}

/// One rendered section of the plant list.
private struct PlantGroup: Identifiable {
    let id: String
    let title: String
    let items: [PlantInstanceDetail]
}

private struct PlantRowView: View {
    let detail: PlantInstanceDetail

    var body: some View {
        HStack(spacing: 14) {
            photo
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.catalog.name)
                    .font(.headline)
                Text(detail.catalog.genus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(detail.instance.vendor) · \(detail.instance.arrivedOn.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !detail.instance.createdByName.isEmpty {
                    Label("Added by \(detail.instance.createdByName)", systemImage: "person.crop.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var photo: some View {
        if let data = detail.instance.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "leaf")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
