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
    @Published private(set) var isLoadingInventory = true
    @Published private(set) var isCloudEnabled = true
    @Published private(set) var isListening = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private var modelContext: ModelContext?
    private let cloudRepo = CloudKitPlantRepository()
    private var localRepo: SwiftDataPlantRepository?
    private var pollTask: Task<Void, Never>?
    private var photoTask: Task<Void, Never>?
    private var hasDisplayedCloudList = false

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
                user = GardensUser(id: "icloud", email: nil, displayName: "iCloud")
                statusMessage = "Loading plants from iCloud…"
                async let recordName = cloudRepo.userRecordName()
                startPolling()
                await refreshCloudInstances()
                if let name = try? await recordName {
                    user = GardensUser(id: name, email: nil, displayName: "iCloud")
                }
            case .noAccount:
                user = nil
                stopPolling()
                isLoadingInventory = false
                statusMessage = "Sign into iCloud in Settings to share inventory"
                await refreshLocalInstances()
            case .restricted:
                user = nil
                stopPolling()
                isLoadingInventory = false
                errorMessage = "iCloud is restricted on this device."
                await refreshLocalInstances()
            case .couldNotDetermine:
                user = nil
                stopPolling()
                isLoadingInventory = false
                errorMessage = "Couldn’t determine iCloud status. Try again."
                await refreshLocalInstances()
            case .temporarilyUnavailable:
                user = nil
                stopPolling()
                isLoadingInventory = false
                errorMessage = "iCloud is temporarily unavailable."
                await refreshLocalInstances()
            @unknown default:
                user = nil
                stopPolling()
                isLoadingInventory = false
                await refreshLocalInstances()
            }
        } catch {
            user = nil
            stopPolling()
            isLoadingInventory = false
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

    func updatePlantPhoto(instanceID: UUID, photoData: Data?, photoCredit: String?) async throws {
        try await repository.updateInstancePhoto(instanceID: instanceID, photoData: photoData, photoCredit: photoCredit)
        await refresh()
    }

    func deletePlant(instanceID: UUID) async throws {
        try await repository.deleteInstance(instanceID: instanceID)
        if usesSharedCloud, let localRepo {
            do {
                try await localRepo.deleteInstance(instanceID: instanceID)
            } catch RepositoryError.instanceNotFound {
                // Shared plants are not copied into the on-device store.
            }
        }
        instances.removeAll { $0.instance.id == instanceID }
        await refresh()
    }

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
        photoTask?.cancel()
        photoTask = nil
        isListening = false
    }

    private func refreshCloudInstances() async {
        if !hasDisplayedCloudList { isLoadingInventory = true }
        photoTask?.cancel()
        do {
            let list = try await cloudRepo.fetchInstances()
            instances = list
            hasDisplayedCloudList = true
            isLoadingInventory = false
            statusMessage = "iCloud sync · \(list.count) plant\(list.count == 1 ? "" : "s")"
            photoTask = Task { [weak self] in
                await self?.attachPhotos()
            }
        } catch {
            isLoadingInventory = false
            errorMessage = error.localizedDescription
        }
    }

    private func attachPhotos() async {
        let missing = instances.filter { $0.instance.photoData == nil }.map(\.instance.id)
        let chunks = stride(from: 0, to: missing.count, by: 6).map { start in
            Array(missing[start..<min(start + 6, missing.count)])
        }
        guard !chunks.isEmpty else { return }
        await withTaskGroup(of: [UUID: Data].self) { group in
            var next = 0
            let width = min(4, chunks.count)
            for _ in 0..<width {
                let chunk = chunks[next]
                next += 1
                group.addTask { await self.cloudRepo.fetchPhotoData(for: chunk) }
            }
            while let batch = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }
                applyPhotos(batch)
                if next < chunks.count {
                    let chunk = chunks[next]
                    next += 1
                    group.addTask { await self.cloudRepo.fetchPhotoData(for: chunk) }
                }
            }
        }
    }

    private func applyPhotos(_ photos: [UUID: Data]) {
        guard !photos.isEmpty else { return }
        instances = instances.map { detail in
            guard detail.instance.photoData == nil, let data = photos[detail.instance.id] else { return detail }
            var copy = detail
            copy.instance.photoData = data
            return copy
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
