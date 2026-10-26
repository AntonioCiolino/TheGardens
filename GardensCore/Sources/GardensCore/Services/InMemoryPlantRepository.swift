import Foundation

/// Ephemeral store for tests and offline demos — same `PlantRepository` contract as CloudKit/SwiftData.
public final class InMemoryPlantRepository: PlantRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var catalog: [UUID: PlantCatalogItem] = [:]
    private var instances: [UUID: PlantInstance] = [:]
    private var careEvents: [UUID: CareEvent] = [:]

    public init() {}

    public func fetchCatalog() async throws -> [PlantCatalogItem] {
        lock.withLock {
            catalog.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    public func fetchInstances() async throws -> [PlantInstanceDetail] {
        let (catalogSnap, instancesSnap) = lock.withLock { (catalog, instances) }
        return instancesSnap.values
            .sorted { $0.arrivedOn > $1.arrivedOn }
            .compactMap { instance in
                guard let item = catalogSnap[instance.catalogItemID] else { return nil }
                return PlantInstanceDetail(instance: instance, catalog: item)
            }
    }

    public func destination(for instanceID: UUID) async throws -> PlantInstanceDestination? {
        let (catalogSnap, instancesSnap, careSnap) = lock.withLock {
            (catalog, instances, careEvents)
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

        var details: [PlantInstanceDetail] = []
        details.reserveCapacity(draft.quantity)

        lock.lock()
        defer { lock.unlock() }

        for _ in 0..<draft.quantity {
            let instance = PlantInstance(
                catalogItemID: catalogItem.id,
                arrivedOn: arrivedOn,
                vendor: vendor,
                photoData: draft.photoData
            )
            instances[instance.id] = instance
            details.append(PlantInstanceDetail(instance: instance, catalog: catalogItem))
        }

        return PlantArrivalBatch(catalog: catalogItem, instances: details)
    }

    public func addCareEvent(_ event: CareEvent) async throws {
        lock.lock()
        defer { lock.unlock() }
        guard instances[event.instanceID] != nil else {
            throw InMemoryRepositoryError.instanceNotFound
        }
        careEvents[event.id] = event
    }

    public func updateCareProfile(catalogItemID: UUID, profile: PlantCareProfile) async throws {
        lock.lock()
        defer { lock.unlock() }
        guard var item = catalog[catalogItemID] else {
            throw InMemoryRepositoryError.catalogNotFound
        }
        item = PlantCatalogItem(
            id: item.id,
            name: item.name,
            genus: item.genus,
            careProfile: profile,
            createdAt: item.createdAt
        )
        catalog[catalogItemID] = item
    }

    public func referencePhoto(for catalogItemID: UUID) async throws -> Data? {
        lock.withLock {
            instances.values
                .filter { $0.catalogItemID == catalogItemID }
                .sorted { $0.createdAt > $1.createdAt }
                .compactMap(\.photoData)
                .first
        }
    }

    private func resolveCatalog(for draft: PlantIntakeDraft) throws -> PlantCatalogItem {
        switch draft.catalogMode {
        case .existingType(let catalogItemID):
            lock.lock()
            defer { lock.unlock() }
            guard let item = catalog[catalogItemID] else {
                throw InMemoryRepositoryError.catalogNotFound
            }
            return item

        case .newOrMatchType:
            let existing = lock.withLock { Array(catalog.values) }
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
            lock.withLock { catalog[item.id] = item }
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

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
