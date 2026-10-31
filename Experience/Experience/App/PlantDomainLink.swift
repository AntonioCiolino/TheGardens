import GardensCore

/// The guest app links the same plant package as Gardens Intake.
/// Plant screens are not in this pass; this reference keeps the dependency real.
enum PlantDomainLink {
    static let moduleName = String(reflecting: PlantCatalogItem.self)
}
