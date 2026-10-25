import SwiftUI
import SwiftData

@main
struct GardensApp: App {
    @State private var showSplash = true
    /// Random brand treatment each launch for now.
    /// Later: persist a user pick or drive from settings.
    @State private var splashStyle = SplashBrandStyle.random()

    var body: some Scene {
        WindowGroup {
            ZStack {
                PlantListView()
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashView(style: splashStyle)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.55), value: showSplash)
            .task {
                try? await Task.sleep(for: .seconds(3.5))
                showSplash = false
            }
        }
        .modelContainer(for: [
            CatalogItemEntity.self,
            PlantInstanceEntity.self,
            CareEventEntity.self,
        ])
    }
}
