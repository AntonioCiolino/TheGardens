import SwiftUI
import SwiftData
import UIKit
import GardensCore

/// Full-screen guest view: photo, name, and suggested care. Nothing else.
struct GuestPlantView: View {
    let instanceID: UUID
    var onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @StateObject private var loader = GuestPlantLoader()

    var body: some View {
        NavigationStack {
            Group {
                if let destination = loader.destination {
                    content(destination)
                } else if loader.isLoading {
                    ProgressView("Loading…")
                } else {
                    Text(loader.errorMessage ?? "That plant isn't here.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(GardensSplashGreen.ignoresSafeArea())
            .navigationTitle(loader.destination?.catalog.name ?? "Plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
            .task {
                await loader.load(instanceID: instanceID, modelContext: modelContext)
            }
        }
    }

    private func content(_ destination: PlantInstanceDestination) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                photo(destination)
                Text(destination.catalog.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                careSection(destination)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background { BrandWatermark(opacity: 0.14) }
    }

    @ViewBuilder
    private func photo(_ destination: PlantInstanceDestination) -> some View {
        if let data = destination.instance.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.96, green: 0.97, blue: 0.95))
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "camera")
                            .font(.title)
                        Text("No photo yet")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Color(red: 0.12, green: 0.18, blue: 0.13))
                }
        }
    }

    private func careSection(_ destination: PlantInstanceDestination) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            group(title: "Care", body: destination.careProfile.careInstructions)
            group(title: "Watering check", body: destination.careProfile.wateringCheckGuidance)
            group(title: "Health check", body: destination.careProfile.healthCheckGuidance)
        }
        .padding(16)
        .background(Color(red: 0.96, green: 0.97, blue: 0.95), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(Color(red: 0.12, green: 0.18, blue: 0.13))
    }

    private func group(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(body.isEmpty ? "Not set yet." : body)
                .font(.body)
                .foregroundStyle(body.isEmpty ? Color(red: 0.12, green: 0.18, blue: 0.13).opacity(0.55) : Color(red: 0.12, green: 0.18, blue: 0.13))
        }
    }
}

@MainActor
final class GuestPlantLoader: ObservableObject {
    @Published private(set) var destination: PlantInstanceDestination?
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    private let lookup = IntakePlantLookup()

    func load(instanceID: UUID, modelContext: ModelContext) async {
        let cache = ViewedPlantCache(modelContext: modelContext)
        do {
            if let remote = try await lookup.destination(for: instanceID) {
                try cache.save(remote)
                destination = remote
                isLoading = false
                return
            }
            errorMessage = "That plant isn't here."
            isLoading = false
        } catch {
            if let cached = try? cache.destination(for: instanceID) {
                destination = cached
                isLoading = false
                return
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isLoading = false
        }
    }
}
