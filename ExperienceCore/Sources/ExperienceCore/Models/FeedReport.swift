import Foundation

/// Why a guest flagged a post. Shown in the report sheet and stored with the report.
public enum ReportReason: String, CaseIterable, Identifiable, Sendable, Codable {
    case objectionable
    case spam
    case harassment
    case other

    public var id: String { rawValue }

    /// Short label for the report menu.
    public var label: String {
        switch self {
        case .objectionable: return "Objectionable or inappropriate"
        case .spam: return "Spam or misleading"
        case .harassment: return "Harassment or hate"
        case .other: return "Something else"
        }
    }
}

/// A guest's report about a post. Stored in the shared feed so the operator can review and act.
public struct FeedReport: Identifiable, Hashable, Sendable {
    public var id: UUID
    /// The post being reported.
    public var postID: UUID
    /// The reported post's author record name, when known.
    public var authorRecordName: String?
    public var reason: ReportReason
    /// The reporting guest's CloudKit user record name, when known.
    public var reporterRecordName: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        postID: UUID,
        authorRecordName: String? = nil,
        reason: ReportReason,
        reporterRecordName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.postID = postID
        self.authorRecordName = authorRecordName
        self.reason = reason
        self.reporterRecordName = reporterRecordName
        self.createdAt = createdAt
    }
}
