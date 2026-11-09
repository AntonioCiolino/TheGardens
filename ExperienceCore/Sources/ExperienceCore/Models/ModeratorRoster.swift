import Foundation

/// Who may take posts down, and the rules for automatic hiding.
///
/// Moderators are identified by their CloudKit **user record name** (the stable id behind
/// `CKContainer.userRecordID()`), stored in a shared `Moderators` record in the public database.
/// Keeping the roster server-side means an employee can be added or removed without shipping a
/// new build — any existing moderator can promote another guest from inside the app.
public enum ModerationPolicy {
    /// A post hidden for everyone once this many distinct reports accumulate.
    /// One report is enough for a small, trusted garden audience; raise this if reports get noisy.
    public static let autoHideReportThreshold = 1

    /// CloudKit record name of the shared moderator roster.
    public static let rosterRecordName = "moderators"

    /// Record-name seeds used to bootstrap the roster the first time it is created.
    /// Replace the placeholders with the operators' real CloudKit user record names
    /// (surface yours with `ExperienceSession.currentUserRecordName`, shown in the About screen).
    /// Until a real id is present, the first guest to open the moderator tools becomes the
    /// bootstrap moderator so you are never locked out.
    public static let seedModeratorRecordNames: [String] = [
        // "_<antonio-user-record-name>",
        // "_<jen-user-record-name>",
    ]
}

/// The shared set of moderator user record names.
public struct ModeratorRoster: Equatable, Sendable {
    public var recordNames: Set<String>

    public init(recordNames: Set<String> = []) {
        self.recordNames = recordNames
    }

    public func contains(_ userRecordName: String?) -> Bool {
        guard let name = userRecordName, !name.isEmpty else { return false }
        return recordNames.contains(name)
    }

    public var isEmpty: Bool { recordNames.isEmpty }
}
