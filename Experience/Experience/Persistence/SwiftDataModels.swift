import Foundation
import SwiftData
import ExperienceCore

@Model
final class PostEntity {
    @Attribute(.unique) var id: UUID
    var text: String
    @Attribute(.externalStorage) var imageData: Data?
    var authorName: String
    /// Opaque CloudKit user record name. Not a person's name.
    var authorRecordName: String?
    var createdAt: Date
    var pendingUpload: Bool

    init(from post: Post) {
        id = post.id
        text = post.text
        imageData = post.imageData
        authorName = post.authorName
        authorRecordName = post.authorRecordName
        createdAt = post.createdAt
        pendingUpload = post.pendingUpload
    }

    func apply(_ post: Post) {
        text = post.text
        imageData = post.imageData
        authorName = post.authorName
        authorRecordName = post.authorRecordName
        createdAt = post.createdAt
        pendingUpload = post.pendingUpload
    }

    func toDomain() -> Post {
        Post(
            id: id,
            text: text,
            imageData: imageData,
            authorName: authorName,
            authorRecordName: authorRecordName,
            createdAt: createdAt,
            pendingUpload: pendingUpload
        )
    }
}
