import XCTest
@testable import GardensCore

final class InMemoryPlantRepositoryTests: XCTestCase {
    func testSaveIntakeCreatesCatalogAndUniqueInstances() async throws {
        let repo = InMemoryPlantRepository()
        let service = PlantIntakeService(repository: repo)

        let batch = try await service.saveNewArrival(
            PlantIntakeDraft(
                catalogMode: .newOrMatchType,
                name: "Snake Plant",
                genus: "Dracaena",
                vendor: "Green Supply",
                careProfile: PlantCareProfile(
                    careInstructions: "Bright indirect light",
                    wateringCheckGuidance: "Soil dry 2\" down",
                    healthCheckGuidance: "Check for soft leaves"
                ),
                quantity: 3
            )
        )

        XCTAssertEqual(batch.count, 3)
        XCTAssertEqual(Set(batch.instances.map(\.id)).count, 3)
        XCTAssertEqual(batch.catalog.name, "Snake Plant")

        let listed = try await repo.fetchInstances()
        XCTAssertEqual(listed.count, 3)

        let destination = try await repo.destination(for: batch.instances[0].id)
        XCTAssertEqual(destination?.catalog.genus, "Dracaena")
        XCTAssertEqual(destination?.careProfile.wateringCheckGuidance, "Soil dry 2\" down")
    }

    func testCareEventPersistsOnInstance() async throws {
        let repo = InMemoryPlantRepository()
        let service = PlantIntakeService(repository: repo)
        let batch = try await service.saveNewArrival(
            PlantIntakeDraft(
                name: "Pothos",
                genus: "Epipremnum",
                vendor: "Local",
                quantity: 1
            )
        )
        let instanceID = batch.instances[0].id

        let event = try await service.logCareUpdate(
            CareUpdateDraft(
                instanceID: instanceID,
                kind: .watered,
                wateringObservation: "Soil was dry",
                healthObservation: "Looks healthy",
                notes: "Test record"
            )
        )

        let destination = try await repo.destination(for: instanceID)
        XCTAssertEqual(destination?.careHistory.count, 1)
        XCTAssertEqual(destination?.careHistory.first?.id, event.id)
        XCTAssertEqual(destination?.careHistory.first?.notes, "Test record")
    }

    func testSecondArrivalReusesCatalogType() async throws {
        let repo = InMemoryPlantRepository()
        let service = PlantIntakeService(repository: repo)

        let first = try await service.saveNewArrival(
            PlantIntakeDraft(name: "ZZ Plant", genus: "Zamioculcas", vendor: "A", quantity: 2)
        )
        let second = try await service.saveNewArrival(
            PlantIntakeDraft(name: "zz plant", genus: "zamioculcas", vendor: "B", quantity: 1)
        )

        XCTAssertEqual(first.catalog.id, second.catalog.id)
        let catalog = try await repo.fetchCatalog()
        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(try await repo.fetchInstances().count, 3)
    }
}
