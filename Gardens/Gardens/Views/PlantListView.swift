import SwiftUI
import SwiftData
import GardensCore

struct PlantListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlantInstanceEntity.arrivedOn, order: .reverse)
    private var instances: [PlantInstanceEntity]

    @State private var showingAdd = false
    @State private var batchToPrint: PlantArrivalBatch?

    var body: some View {
        NavigationStack {
            Group {
                if instances.isEmpty {
                    ContentUnavailableView(
                        "No plants yet",
                        systemImage: "leaf",
                        description: Text("Log an arrival — one plant or a whole carton.")
                    )
                } else {
                    List(instances) { entity in
                        if let detail = entity.toDetail() {
                            NavigationLink(value: detail.instance.id) {
                                PlantRowView(detail: detail)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Gardens")
            .navigationDestination(for: UUID.self) { id in
                PlantDetailView(instanceID: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Plant", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                NavigationStack {
                    AddPlantView { batch in
                        batchToPrint = batch
                    }
                }
            }
            .sheet(item: $batchToPrint) { batch in
                BatchLabelPrintView(batch: batch)
            }
        }
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
                .fill(Color(.tertiarySystemFill))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
