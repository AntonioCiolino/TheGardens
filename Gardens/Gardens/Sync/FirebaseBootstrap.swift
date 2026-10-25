import Foundation
import FirebaseCore

/// Detects a real `GoogleService-Info.plist` and boots Firebase once.
enum FirebaseBootstrap {
    /// True when the bundled plist looks like a real Firebase iOS app (not the example stub).
    static var isConfigured: Bool {
        guard
            let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: path),
            let appID = dict["GOOGLE_APP_ID"] as? String,
            let projectID = dict["PROJECT_ID"] as? String
        else { return false }

        let stubMarkers = ["REPLACE_ME", "your-project", "000000000000"]
        if stubMarkers.contains(where: { appID.contains($0) || projectID.contains($0) }) {
            return false
        }
        return !appID.isEmpty && !projectID.isEmpty
    }

    @discardableResult
    static func configureIfNeeded() -> Bool {
        guard isConfigured else { return false }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
    }
}
