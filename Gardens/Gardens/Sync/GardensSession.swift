import Foundation
import SwiftUI
import SwiftData
import CloudKit
import GardensCore

struct GardensUser: Equatable {
    var id: String
    var email: String?
    var displayName: String?
}

/// App-wide iCloud account + plant repository.
/// Shared path: **CloudKit** (Apple) — requires an iCloud / Apple ID on the iPhone.
/// Offline path: on-device SwiftData until iCloud is available.
@MainActor
final class GardensSession: ObservableObject {
    @Published private(set) var user: GardensUser?
    @Published private(set) var instances: [PlantInstanceDetail] = []
    @Published private(set) var isCloudEnabled = true
    @Published private(set) var isListening = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private var modelContext: ModelContext?
    private let cloudRepo = CloudKitPlantRepository()
    private var localRepo: SwiftDataPlantRepository?
    private var pollTask: Task<Void, Never>?

    var repository: any PlantRepository {
        if usesSharedCloud {
            return cloudRepo
        }
        guard let localRepo else {
            fatalError("GardensSession missing local repository — call attach(modelContext:) first.")
        }
        return localRepo
    }

    var usesSharedCloud: Bool {
        user != nil
    }

    init() {
        Task { await refreshAccount() }
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        localRepo = SwiftDataPlantRepository(modelContext: modelContext)
        if !usesSharedCloud {
            Task { await refreshLocalInstances() }
        }
    }

    // MARK: - iCloud (Apple ID)

    /// Checks the device iCloud account. Staff must be signed into iCloud in Settings.
    func refreshAccount() async {
        errorMessage = nil
        do {
            let status = try await cloudRepo.accountStatus()
            switch status {
            case .available:
                let recordName = try await cloudRepo.userRecordName()
                user = GardensUser(
                    id: recordName,
                    email: nil,
                    displayName: "iCloud"
                )
                statusMessage = "iCloud connected — inventory syncs across team iPhones"
                startPolling()
                await refreshCloudInstances()
            case .noAccount:
                user = nil
                stopPolling()
                statusMessage = "Sign into iCloud in Settings to share inventory"
                await refreshLocalInstances()
            case .restricted:
                user = nil
                stopPolling()
                errorMessage = "iCloud is restricted on this device."
                await refreshLocalInstances()
            case .couldNotDetermine:
                user = nil
                stopPolling()
                errorMessage = "Couldn’t determine iCloud status. Try again."
                await refreshLocalInstances()
            case .temporarilyUnavailable:
                user = nil
                stopPolling()
                errorMessage = "iCloud is temporarily unavailable."
                await refreshLocalInstances()
            @unknown default:
                user = nil
                stopPolling()
                await refreshLocalInstances()
            }
        } catch {
            user = nil
            stopPolling()
            errorMessage = error.localizedDescription
            await refreshLocalInstances()
        }
    }

    func signOutLocally() {
        // CloudKit uses the system iCloud account — we only drop the in-app session view
        // and fall back to on-device data until iCloud is available again.
        stopPolling()
        user = nil
        Task { await refreshLocalInstances() }
        statusMessage = "Using this iPhone only — reconnect iCloud under Sync to share"
    }

    // MARK: - Data

    func refresh() async {
        if usesSharedCloud {
            await refreshCloudInstances()
        } else {
            await refreshAccount()
            if !usesSharedCloud {
                await refreshLocalInstances()
            }
        }
    }

    /// Writes one catalog + instance + care event through the active repository, then reloads.
    /// Use after Connect iCloud to verify CloudKit accepts a real record.
    @discardableResult
    func writeTestRecord() async -> String {
        errorMessage = nil
        do {
            if user == nil {
                await refreshAccount()
            }
            let service = PlantIntakeService(repository: repository)
            let stamp = Date().formatted(date: .numeric, time: .shortened)
            let batch = try await service.saveNewArrival(
                PlantIntakeDraft(
                    catalogMode: .newOrMatchType,
                    name: "Gardens Sync Test",
                    genus: "Testus",
                    vendor: "Setup Check",
                    careProfile: PlantCareProfile(
                        careInstructions: "Created by Sync → Write test record",
                        wateringCheckGuidance: "Ignore — smoke test",
                        healthCheckGuidance: "Ignore — smoke test"
                    ),
                    quantity: 1
                )
            )
            let instanceID = batch.instances[0].id
            _ = try await service.logCareUpdate(
                CareUpdateDraft(
                    instanceID: instanceID,
                    kind: .note,
                    notes: "CloudKit smoke test at \(stamp)"
                )
            )
            await refresh()
            let message = "Test OK — plant \(instanceID.uuidString.prefix(8))… with care note (\(usesSharedCloud ? "iCloud" : "this iPhone only"))"
            statusMessage = message
            return message
        } catch {
            errorMessage = error.localizedDescription
            return "Test failed: \(error.localizedDescription)"
        }
    }

    private func startPolling() {
        stopPolling()
        isListening = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, self.usesSharedCloud else { continue }
                await self.refreshCloudInstances()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isListening = false
    }

    private func refreshCloudInstances() async {
        do {
            let list = try await cloudRepo.fetchInstances()
            instances = list
            statusMessage = "iCloud sync · \(list.count) plant\(list.count == 1 ? "" : "s")"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLocalInstances() async {
        guard let localRepo else { return }
        do {
            instances = try await localRepo.fetchInstances()
            if statusMessage == nil || user == nil {
                statusMessage = "On this iPhone only — connect iCloud under Sync to share"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
