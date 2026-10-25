import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import GardensCore

/// Shared multi-user inventory: each catalog / instance / care event is its own Firestore document.
/// Photos live in Firebase Storage (not embedded in documents).
@MainActor
final class FirestorePlantRepository: PlantRepository {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var photoCache: [UUID: Data] = [:]

    func fetchCatalog() async throws -> [PlantCatalogItem] {
        try requireAuth()
        let snap = try await db.collection(FirestorePaths.catalog)
            .order(by: "name")
            .getDocuments()
        return snap.documents.compactMap { FirestoreMappers.catalog(from: $0.data(), id: $0.documentID) }
    }

    func fetchInstances() async throws -> [PlantInstanceDetail] {
        try requireAuth()
        let catalogByID = Dictionary(uniqueKeysWithValues: try await fetchCatalog().map { ($0.id, $0) })
        let snap = try await db.collection(FirestorePaths.instances)
            .order(by: "arrivedOn", descending: true)
            .getDocuments()

        var details: [PlantInstanceDetail] = []
        for doc in snap.documents {
            let data = doc.data()
            let photo = try await loadPhoto(from: data)
            guard
                let instance = FirestoreMappers.instance(from: data, id: doc.documentID, photoData: photo),
                let catalog = catalogByID[instance.catalogItemID]
            else { continue }
            details.append(PlantInstanceDetail(instance: instance, catalog: catalog))
        }
        return details
    }

    func destination(for instanceID: UUID) async throws -> PlantInstanceDestination? {
        try requireAuth()
        let instanceRef = db.collection(FirestorePaths.instances).document(instanceID.uuidString)
        let instanceSnap = try await instanceRef.getDocument()
        guard instanceSnap.exists, let data = instanceSnap.data() else { return nil }

        let photo = try await loadPhoto(from: data)
        guard let instance = FirestoreMappers.instance(from: data, id: instanceSnap.documentID, photoData: photo)
        else { return nil }

        let catalogRef = db.collection(FirestorePaths.catalog).document(instance.catalogItemID.uuidString)
        let catalogSnap = try await catalogRef.getDocument()
        guard
            catalogSnap.exists,
            let catalogData = catalogSnap.data(),
            let catalog = FirestoreMappers.catalog(from: catalogData, id: catalogSnap.documentID)
        else { return nil }

        let historySnap = try await db.collection(FirestorePaths.careEvents)
            .whereField("instanceID", isEqualTo: instanceID.uuidString)
            .getDocuments()
        let history = historySnap.documents.compactMap {
            FirestoreMappers.careEvent(from: $0.data(), id: $0.documentID)
        }

        return PlantInstanceDestination(
            instance: instance,
            catalog: catalog,
            careProfile: catalog.careProfile,
            careHistory: history
        )
    }

    func saveIntake(_ draft: PlantIntakeDraft) async throws -> PlantArrivalBatch {
        try requireAuth()
        let catalog = try await resolveCatalog(for: draft)
        let arrivedOn = Calendar.current.startOfDay(for: draft.arrivedOn)
        let vendor = draft.vendor.trimmingCharacters(in: .whitespacesAndNewlines)

        var details: [PlantInstanceDetail] = []
        details.reserveCapacity(draft.quantity)

        for _ in 0..<draft.quantity {
            let instanceID = UUID()
            var photoPath: String?
            if let photoData = draft.photoData {
                photoPath = try await uploadPhoto(photoData, instanceID: instanceID)
                photoCache[instanceID] = photoData
            }

            let instance = PlantInstance(
                id: instanceID,
                catalogItemID: catalog.id,
                arrivedOn: arrivedOn,
                vendor: vendor,
                photoData: draft.photoData,
                createdAt: Date()
            )
            try await db.collection(FirestorePaths.instances)
                .document(instanceID.uuidString)
                .setData(FirestoreMappers.instanceData(instance, photoPath: photoPath))
            details.append(PlantInstanceDetail(instance: instance, catalog: catalog))
        }

        return PlantArrivalBatch(catalog: catalog, instances: details)
    }

    func addCareEvent(_ event: CareEvent) async throws {
        try requireAuth()
        let instanceSnap = try await db.collection(FirestorePaths.instances)
            .document(event.instanceID.uuidString)
            .getDocument()
        guard instanceSnap.exists else { throw RepositoryError.instanceNotFound }

        try await db.collection(FirestorePaths.careEvents)
            .document(event.id.uuidString)
            .setData(FirestoreMappers.careEventData(event))
    }

    func updateCareProfile(catalogItemID: UUID, profile: PlantCareProfile) async throws {
        try requireAuth()
        let ref = db.collection(FirestorePaths.catalog).document(catalogItemID.uuidString)
        let snap = try await ref.getDocument()
        guard snap.exists,
              let data = snap.data(),
              var item = FirestoreMappers.catalog(from: data, id: snap.documentID)
        else { throw RepositoryError.catalogNotFound }

        item = PlantCatalogItem(
            id: item.id,
            name: item.name,
            genus: item.genus,
            careProfile: profile,
            createdAt: item.createdAt
        )
        try await ref.setData(FirestoreMappers.catalogData(item), merge: true)
    }

    func referencePhoto(for catalogItemID: UUID) async throws -> Data? {
        try requireAuth()
        // No composite index required — sort client-side.
        let snap = try await db.collection(FirestorePaths.instances)
            .whereField("catalogItemID", isEqualTo: catalogItemID.uuidString)
            .getDocuments()

        let sorted = snap.documents.sorted { lhs, rhs in
            let l = (lhs.data()["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
            let r = (rhs.data()["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
            return l > r
        }

        for doc in sorted.prefix(12) {
            if let photo = try await loadPhoto(from: doc.data()) {
                return photo
            }
        }
        return nil
    }

    // MARK: - Live list

    /// Observe instance documents; caller joins catalog and refreshes UI.
    func listenToInstances(
        onChange: @escaping @MainActor ([QueryDocumentSnapshot]) -> Void
    ) -> ListenerRegistration {
        db.collection(FirestorePaths.instances)
            .order(by: "arrivedOn", descending: true)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else { return }
                Task { @MainActor in
                    onChange(docs)
                }
            }
    }

    func detail(
        from instanceDoc: QueryDocumentSnapshot,
        catalogByID: [UUID: PlantCatalogItem]
    ) async -> PlantInstanceDetail? {
        let data = instanceDoc.data()
        let photo = try? await loadPhoto(from: data)
        guard
            let instance = FirestoreMappers.instance(from: data, id: instanceDoc.documentID, photoData: photo),
            let catalog = catalogByID[instance.catalogItemID]
        else { return nil }
        return PlantInstanceDetail(instance: instance, catalog: catalog)
    }

    // MARK: - Private

    private func requireAuth() throws {
        guard Auth.auth().currentUser != nil else {
            throw RepositoryError.notSignedIn
        }
    }

    private func resolveCatalog(for draft: PlantIntakeDraft) async throws -> PlantCatalogItem {
        switch draft.catalogMode {
        case .existingType(let catalogItemID):
            let snap = try await db.collection(FirestorePaths.catalog)
                .document(catalogItemID.uuidString)
                .getDocument()
            guard
                snap.exists,
                let data = snap.data(),
                let item = FirestoreMappers.catalog(from: data, id: snap.documentID)
            else { throw RepositoryError.catalogNotFound }
            return item

        case .newOrMatchType:
            let existing = try await fetchCatalog()
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
            try await db.collection(FirestorePaths.catalog)
                .document(item.id.uuidString)
                .setData(FirestoreMappers.catalogData(item))
            return item
        }
    }

    private func uploadPhoto(_ data: Data, instanceID: UUID) async throws -> String {
        let path = FirestorePaths.photoPath(instanceID: instanceID)
        let ref = storage.reference().child(path)
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: meta)
        return path
    }

    private func loadPhoto(from data: [String: Any]) async throws -> Data? {
        guard let path = data["photoPath"] as? String, !path.isEmpty else { return nil }
        if let idString = data["id"] as? String, let id = UUID(uuidString: idString),
           let cached = photoCache[id] {
            return cached
        }
        let ref = storage.reference().child(path)
        let bytes = try await ref.data(maxSize: 8 * 1024 * 1024)
        if let idString = data["id"] as? String, let id = UUID(uuidString: idString) {
            photoCache[id] = bytes
        }
        return bytes
    }
}
