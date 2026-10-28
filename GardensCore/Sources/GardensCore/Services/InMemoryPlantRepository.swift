import Foundation
import os

/// Ephemeral store for tests and offline demos — same `PlantRepository` contract as CloudKit/SwiftData.
public final class InMemoryPlantRepository: PlantRepository, @unchecked Sendable {
    private struct Store {
        var catalog: [UUID: PlantCatalogItem] = [:]
        var instances: [UUID: PlantInstance] = [:]
        var careEvents: [UUID: CareEvent] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: Store())

    public init() {}

    public func fetchCatalog() async throws -> [PlantCatalogItem] {
        state.withLock { store in
            let live = Set(store.instances.values.map(\.catalogItemID))
            let stale = store.catalog.keys.filter { !live.contains($0) }
            for id in stale {
                store.catalog.removeValue(forKey: id)
            }
            return store.catalog.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    public func fetchInstances() async throws -> [PlantInstanceDetail] {
        let (catalogSnap, instancesSnap) = state.withLock { store in
            (store.catalog, store.instances)
        }
        return instancesSnap.values
            .sorted { $0.arrivedOn > $1.arrivedOn }
            .compactMap { instance in
                guard let item = catalogSnap[instance.catalogItemID] else { return nil }
                return PlantInstanceDetail(instance: instance, catalog: item)
            }
    }

    public func destination(for instanceID: UUID) async throws -> PlantInstanceDestination? {
        let (catalogSnap, instancesSnap, careSnap) = state.withLock { store in
            (store.catalog, store.instances, store.careEvents)
        }
        guard
            let instance = instancesSnap[instanceID],
            let item = catalogSnap[instance.catalogItemID]
        else { return nil }
        let history = careSnap.values.filter { $0.instanceID == instanceID }
        return PlantInstanceDestination(
            instance: instance,
            catalog: item,
            careProfile: item.careProfile,
            careHistory: history
        )
    }

    public func saveIntake(_ draft: PlantIntakeDraft) async throws -> PlantArrivalBatch {
        let catalogItem = try resolveCatalog(for: draft)
        let arrivedOn = Calendar.current.startOfDay(for: draft.arrivedOn)
        let vendor = draft.vendor.trimmingCharacters(in: .whitespacesAndNewlines)

        return state.withLock { store in
            var details: [PlantInstanceDetail] = []
            details.reserveCapacity(draft.quantity)
            for _ in 0..<draft.quantity {
                let instance = PlantInstance(
                    catalogItemID: catalogItem.id,
                    arrivedOn: arrivedOn,
                    vendor: vendor,
                    photoData: draft.photoData,
                    photoCredit: draft.photoCredit
                )
                store.instances[instance.id] = instance
                details.append(PlantInstanceDetail(instance: instance, catalog: catalogItem))
            }
            return PlantArrivalBatch(catalog: catalogItem, instances: details)
        }
    }

    public func addCareEvent(_ event: CareEvent) async throws {
        try state.withLock { store in
            guard store.instances[event.instanceID] != nil else {
                throw InMemoryRepositoryError.instanceNotFound
            }
            store.careEvents[event.id] = event
        }
    }

    public func updateInstancePhoto(instanceID: UUID, photoData: Data?, photoCredit: String?) async throws {
        try state.withLock { store in
            guard var instance = store.instances[instanceID] else {
                throw InMemoryRepositoryError.instanceNotFound
            }
            instance.photoData = photoData
            instance.photoCredit = photoData == nil ? nil : photoCredit
            store.instances[instanceID] = instance
        }
    }

    public func deleteInstance(instanceID: UUID) async throws {
        try state.withLock { store in
            guard let removed = store.instances.removeValue(forKey: instanceID) else {
                throw InMemoryRepositoryError.instanceNotFound
            }
            store.careEvents = store.careEvents.filter { $0.value.instanceID != instanceID }
            let stillUsed = store.instances.values.contains { $0.catalogItemID == removed.catalogItemID }
            if !stillUsed {
                store.catalog.removeValue(forKey: removed.catalogItemID)
            }
        }
    }

    public func updateCareProfile(catalogItemID: UUID, profile: PlantCareProfile) async throws {
        try state.withLock { store in
            guard var item = store.catalog[catalogItemID] else {
                throw InMemoryRepositoryError.catalogNotFound
            }
            item = PlantCatalogItem(
                id: item.id,
                name: item.name,
                genus: item.genus,
                careProfile: profile,
                createdAt: item.createdAt
            )
            store.catalog[catalogItemID] = item
        }
    }

    public func referencePhoto(for catalogItemID: UUID) async throws -> Data? {
        state.withLock { store in
            store.instances.values
                .filter { $0.catalogItemID == catalogItemID }
                .sorted { $0.createdAt > $1.createdAt }
                .compactMap(\.photoData)
                .first
        }
    }

    private func resolveCatalog(for draft: PlantIntakeDraft) throws -> PlantCatalogItem {
        switch draft.catalogMode {
        case .existingType(let catalogItemID):
            return try state.withLock { store in
                guard let item = store.catalog[catalogItemID] else {
                    throw InMemoryRepositoryError.catalogNotFound
                }
                return item
            }

        case .newOrMatchType:
            let existing = state.withLock { store in Array(store.catalog.values) }
            if let match = PlantCatalogMatcher.findExisting(
                name: draft.name,
                genus: draft.genus,
                in: existing
            ) {
                return match
            }
            let item = PlantCatalogItem(
                name: draft.name,
                genus: draft.genus,
                careProfile: draft.careProfile
            )
            state.withLock { store in store.catalog[item.id] = item }
            return item
        }
    }
}

public enum InMemoryRepositoryError: LocalizedError {
    case instanceNotFound
    case catalogNotFound

    public var errorDescription: String? {
        switch self {
        case .instanceNotFound: return "Instance not found."
        case .catalogNotFound: return "Catalog item not found."
        }
    }
}
