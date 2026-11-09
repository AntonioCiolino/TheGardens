import Foundation

/// Persistence boundary for the guest feed.
/// iOS uses SwiftData on device and CloudKit when iCloud is available.
public protocol FeedRepository: AnyObject {
    func fetchPosts() async throws -> [Post]
    func publish(_ draft: PostDraft) async throws -> Post
    /// Submits a guest's report about a post so the operator can review and remove it.
    func submitReport(_ report: FeedReport) async throws
}
