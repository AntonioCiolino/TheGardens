import SwiftUI
import SwiftData

@main
struct ExperienceApp: App {
    private let modelContainer = LocalFeedStore.makeContainer()
    @StateObject private var moderation: ModerationStore
    @StateObject private var session: ExperienceSession
    @StateObject private var geofence = GardenGeofenceMonitor()

    init() {
        let moderation = ModerationStore()
        _moderation = StateObject(wrappedValue: moderation)
        _session = StateObject(wrappedValue: ExperienceSession(moderation: moderation))
    }

    var body: some Scene {
        WindowGroup {
            FeedRoot(session: session, geofence: geofence)
                .environmentObject(moderation)
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @State private var splashRun = 0

    var body: some View {
        ZStack {
            FeedView()
                .opacity(showSplash ? 0 : 1)
                .allowsHitTesting(!showSplash)

            if showSplash {
                SplashView(placeName: geofence.welcomePlace?.name)
                    .id(splashRun)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: showSplash)
        .environmentObject(session)
        .environmentObject(geofence)
        .onAppear {
            geofence.start()
            session.attach(modelContext: modelContext)
        }
        .task(id: splashRun) {
            try? await Task.sleep(for: .seconds(5.5))
            showSplash = false
            geofence.dismissWelcome()
        }
        .onChange(of: geofence.splashReplayID) { _, replay in
            guard replay > 0 else { return }
            showSplash = true
            splashRun = replay
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !showSplash {
                geofence.appBecameActive()
            }
        }
    }
}
