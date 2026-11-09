import Foundation

/// The app’s own voice on the feed. Guest posts use an iCloud user id.
/// This record is Jen’s, stored under a stable app id until admin editing exists.
public enum AppVoice {
    public static let recordName = "gardens-app"
    public static let authorName = "Jen"
    /// CloudKit record name for the message of the day. Not listed in the guest feed.
    public static let messageRecordName = "message-of-the-day"
    public static let messageID = UUID(uuidString: "F3C1A9E2-7B44-4D18-9A60-1C8E5B20D4A7")!

    public static let seededCareNote = """
    I’m glad you’re here. Take your time, look at what is growing, and let yourself be looked after for a little while. You belong in this place.
    """

    public static func seededMessage(createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Post {
        Post(
            id: messageID,
            text: seededCareNote,
            authorName: authorName,
            authorRecordName: recordName,
            createdAt: createdAt,
            pendingUpload: false
        )
    }
}
