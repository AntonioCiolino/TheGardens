import Foundation
import FirebaseFirestore
import GardensCore

enum FirestoreMappers {
    static func catalogData(_ item: PlantCatalogItem) -> [String: Any] {
        [
            "id": item.id.uuidString,
            "name": item.name,
            "genus": item.genus,
            "careInstructions": item.careProfile.careInstructions,
            "wateringCheckGuidance": item.careProfile.wateringCheckGuidance,
            "healthCheckGuidance": item.careProfile.healthCheckGuidance,
            "createdAt": Timestamp(date: item.createdAt),
            "updatedAt": Timestamp(date: Date()),
        ]
    }

    static func catalog(from data: [String: Any], id: String) -> PlantCatalogItem? {
        guard let uuid = UUID(uuidString: (data["id"] as? String) ?? id) else { return nil }
        return PlantCatalogItem(
            id: uuid,
            name: data["name"] as? String ?? "",
            genus: data["genus"] as? String ?? "",
            careProfile: PlantCareProfile(
                careInstructions: data["careInstructions"] as? String ?? "",
                wateringCheckGuidance: data["wateringCheckGuidance"] as? String ?? "",
                healthCheckGuidance: data["healthCheckGuidance"] as? String ?? ""
            ),
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    static func instanceData(_ instance: PlantInstance, photoPath: String?) -> [String: Any] {
        var data: [String: Any] = [
            "id": instance.id.uuidString,
            "catalogItemID": instance.catalogItemID.uuidString,
            "arrivedOn": Timestamp(date: instance.arrivedOn),
            "vendor": instance.vendor,
            "createdAt": Timestamp(date: instance.createdAt),
            "updatedAt": Timestamp(date: Date()),
        ]
        if let photoPath {
            data["photoPath"] = photoPath
        }
        return data
    }

    static func instance(from data: [String: Any], id: String, photoData: Data?) -> PlantInstance? {
        guard
            let uuid = UUID(uuidString: (data["id"] as? String) ?? id),
            let catalogString = data["catalogItemID"] as? String,
            let catalogID = UUID(uuidString: catalogString)
        else { return nil }

        return PlantInstance(
            id: uuid,
            catalogItemID: catalogID,
            arrivedOn: (data["arrivedOn"] as? Timestamp)?.dateValue() ?? Date(),
            vendor: data["vendor"] as? String ?? "",
            photoData: photoData,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    static func careEventData(_ event: CareEvent) -> [String: Any] {
        [
            "id": event.id.uuidString,
            "instanceID": event.instanceID.uuidString,
            "kind": event.kind.rawValue,
            "performedAt": Timestamp(date: event.performedAt),
            "wateringObservation": event.wateringObservation,
            "healthObservation": event.healthObservation,
            "notes": event.notes,
            "updatedAt": Timestamp(date: Date()),
        ]
    }

    static func careEvent(from data: [String: Any], id: String) -> CareEvent? {
        guard
            let uuid = UUID(uuidString: (data["id"] as? String) ?? id),
            let instanceString = data["instanceID"] as? String,
            let instanceID = UUID(uuidString: instanceString),
            let kindRaw = data["kind"] as? String,
            let kind = CareEventKind(rawValue: kindRaw)
        else { return nil }

        return CareEvent(
            id: uuid,
            instanceID: instanceID,
            kind: kind,
            performedAt: (data["performedAt"] as? Timestamp)?.dateValue() ?? Date(),
            wateringObservation: data["wateringObservation"] as? String ?? "",
            healthObservation: data["healthObservation"] as? String ?? "",
            notes: data["notes"] as? String ?? ""
        )
    }
}
