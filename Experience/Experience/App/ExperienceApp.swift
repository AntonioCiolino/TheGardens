import SwiftUI
import SwiftData

@main
struct ExperienceApp: App {
    private let modelContainer = LocalFeedStore.makeContainer()
    @StateObject private var session = ExperienceSession()
    @StateObject private var geofence = GardenGeofenceMonitor()

    var body: some Scene {
        WindowGroup {
            FeedRoot(session: session, geofence: geofence)
        }
        .modelContainer(modelContainer)
    }
}

/// On-device feed cache. `cloudKitDatabase: .none` keeps SwiftData off iCloud.
/// Shared posts go through `CloudKitFeedRepository`.
private enum LocalFeedStore {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            PostEntity.self,
            ViewedPlantEntity.self,
        ])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the local feed store: \(error)")
        }
    }
}

private struct FeedRoot: View {
    @ObservedObject var session: ExperienceSession
    @ObservedObject var geofence: GardenGeofenceMonitor
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        FeedView()
            .environmentObject(session)
            .environmentObject(geofence)
            .task {
                session.attach(modelContext: modelContext)
                geofence.start()
            }
    }
}
