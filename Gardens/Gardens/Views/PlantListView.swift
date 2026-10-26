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

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                BrandWatermark(opacity: 0.16)

                Group {
                    if session.instances.isEmpty {
                        ContentUnavailableView(
                            "No plants yet",
                            systemImage: "leaf",
                            description: Text(emptyDescription)
                        )
                    } else {
                        List(session.instances) { detail in
                            NavigationLink(value: detail.instance.id) {
                                PlantRowView(detail: detail)
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.insetGrouped)
                    }
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
                if let status = session.statusMessage, !session.instances.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
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
                    ScanPlantView()
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
            .refreshable {
                await session.refresh()
            }
        }
    }

    private var emptyDescription: String {
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
