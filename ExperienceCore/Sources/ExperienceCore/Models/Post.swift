import Foundation

/// One guest post on the shared feed: a caption, an image, or both.
public struct Post: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var text: String
    public var imageData: Data?
    public var authorName: String
    /// CloudKit user record name (`CKRecord.creatorUserRecordID` / `userRecordID()`). Not a display name.
    public var authorRecordName: String?
    public var createdAt: Date
    /// True when this phone saved the post and iCloud has not accepted it yet.
    public var pendingUpload: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        imageData: Data? = nil,
        authorName: String = "",
        authorRecordName: String? = nil,
        createdAt: Date = Date(),
        pendingUpload: Bool = false
    ) {
        self.id = id
        self.text = text
        self.imageData = imageData
        self.authorName = authorName
        self.authorRecordName = authorRecordName
        self.createdAt = createdAt
        self.pendingUpload = pendingUpload
    }
}

public struct PostDraft: Hashable, Sendable {
    public var text: String
    public var imageData: Data?
    public var authorName: String
    public var authorRecordName: String?

    public init(text: String, imageData: Data? = nil, authorName: String = "", authorRecordName: String? = nil) {
        self.text = text
        self.imageData = imageData
        self.authorName = authorName
        self.authorRecordName = authorRecordName
    }

    /// A caption, a photo, or both. Whitespace-only text does not count.
    public func makePost(id: UUID = UUID(), createdAt: Date = Date()) throws -> Post {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordName = authorRecordName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = (imageData?.isEmpty == false) ? imageData : nil
        guard !text.isEmpty || image != nil else { throw FeedError.emptyPost }
        return Post(
            id: id,
            text: text,
            imageData: image,
            authorName: author,
            authorRecordName: (recordName?.isEmpty == false) ? recordName : nil,
            createdAt: createdAt,
            pendingUpload: false
        )
    }
}

public enum FeedError: LocalizedError, Equatable {
    case emptyPost
    case notSignedIn
    case saveFailed

    public var errorDescription: String? {
        switch self {
        case .emptyPost:
            return "Add a photo or a few words before posting."
        case .notSignedIn:
            return "Sign into iCloud on this iPhone to share posts."
        case .saveFailed:
            return "Couldn’t save this post."
        }
    }
}
