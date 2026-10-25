import SwiftUI
import SwiftData

@main
struct GardensApp: App {
    var body: some Scene {
        WindowGroup {
            PlantListView()
        }
        .modelContainer(for: [
            CatalogItemEntity.self,
            PlantInstanceEntity.self,
            CareEventEntity.self,
        ])
    }
}
