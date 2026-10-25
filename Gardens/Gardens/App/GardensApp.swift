import SwiftUI
import SwiftData

@main
struct GardensApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                PlantListView()
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.55), value: showSplash)
            .task {
                try? await Task.sleep(for: .seconds(1.6))
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
