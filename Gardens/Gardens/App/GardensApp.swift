import SwiftUI
import SwiftData
import GardensCore

@main
struct GardensApp: App {
    @StateObject private var session = GardensSession()
    @State private var showSplash = true
    @State private var splashStyle = SplashBrandStyle.random()
    /// Plant opened from a `gardens://` QR via Camera / Safari / another app.
    @State private var deepLinkPlantID: UUID?
    @State private var openCareFromDeepLink = false

    var body: some Scene {
        WindowGroup {
            RootContainer(
                session: session,
                showSplash: $showSplash,
                splashStyle: splashStyle,
                deepLinkPlantID: $deepLinkPlantID,
                openCareFromDeepLink: $openCareFromDeepLink
            )
            .environmentObject(session)
            .animation(.easeInOut(duration: 0.55), value: showSplash)
            .task {
                try? await Task.sleep(for: .seconds(3.5))
                showSplash = false
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
        }
        .modelContainer(for: [
            CatalogItemEntity.self,
            PlantInstanceEntity.self,
            CareEventEntity.self,
        ])
    }

    private func handleIncomingURL(_ url: URL) {
        guard CompactPlantQR.isGardensPayload(url.absoluteString),
              let id = CompactPlantQR.instanceID(fromScanned: url.absoluteString)
        else { return }
        showSplash = false
        openCareFromDeepLink = true
        deepLinkPlantID = id
    }
}

/// Attaches the SwiftData context to the session once the environment is available.
private struct RootContainer: View {
    @ObservedObject var session: GardensSession
    @Environment(\.modelContext) private var modelContext

    @Binding var showSplash: Bool
    var splashStyle: SplashBrandStyle
    @Binding var deepLinkPlantID: UUID?
    @Binding var openCareFromDeepLink: Bool

    var body: some View {
        ZStack {
            PlantListView(
                deepLinkPlantID: $deepLinkPlantID,
                openCareFromDeepLink: $openCareFromDeepLink
            )
            .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashView(style: splashStyle)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            session.attach(modelContext: modelContext)
        }
    }
}
