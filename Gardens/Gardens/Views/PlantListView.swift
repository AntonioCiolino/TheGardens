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
                        ForEach(session.instances) { detail in
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
