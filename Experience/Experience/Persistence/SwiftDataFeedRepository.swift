import Foundation
import SwiftData
import ExperienceCore

@MainActor
final class SwiftDataFeedRepository: FeedRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchPosts() async throws -> [Post] {
        let descriptor = FetchDescriptor<PostEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func publish(_ draft: PostDraft) async throws -> Post {
        var post = try draft.makePost()
        post.pendingUpload = true
        try upsert(post)
        return post
    }

    func pendingPosts() throws -> [Post] {
        let descriptor = FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.pendingUpload },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func upsert(_ post: Post) throws {
        let id = post.id
        let descriptor = FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(post)
        } else {
            modelContext.insert(PostEntity(from: post))
        }
        try modelContext.save()
    }

    /// Keeps posts that are still waiting to upload. Replaces everything else with the cloud list.
    func replaceCache(with posts: [Post]) throws {
        let incoming = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        let existing = try modelContext.fetch(FetchDescriptor<PostEntity>())
        let existingIDs = Set(existing.map(\.id))
        for entity in existing {
            if let post = incoming[entity.id] {
                var stored = post
                stored.pendingUpload = false
                entity.apply(stored)
            } else if !entity.pendingUpload {
                modelContext.delete(entity)
            }
        }
        for post in posts where !existingIDs.contains(post.id) {
            var stored = post
            stored.pendingUpload = false
            modelContext.insert(PostEntity(from: stored))
        }
        try modelContext.save()
    }
}
