import Foundation

/// Shared Firestore layout for every signed-in Gardens user.
/// One workspace = one nursery inventory (multi-user, record-level sync).
enum FirestorePaths {
    /// Change if you later split multiple nurseries / tenants.
    static let workspaceID = "default"

    static var workspace: String { "workspaces/\(workspaceID)" }
    static var catalog: String { "\(workspace)/catalog" }
    static var instances: String { "\(workspace)/instances" }
    static var careEvents: String { "\(workspace)/careEvents" }

    static func photoPath(instanceID: UUID) -> String {
        "workspaces/\(workspaceID)/photos/\(instanceID.uuidString).jpg"
    }
}
