import Foundation
import SwiftData
import CloudKit
import ExperienceCore

struct ExperienceUser: Equatable {
    var id: String
    var displayName: String?
}

/// Shared path: CloudKit public feed. Offline path: the SwiftData cache, including posts waiting to upload.
/// Any guest may publish. There is no admin check in this scaffold.
@MainActor
final class ExperienceSession: ObservableObject {
    @Published private(set) var user: ExperienceUser?
    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = true
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    /// Keeps GardensCore linked for a later plant screen.
    let sharedPlantDomain = PlantDomainLink.moduleName

    private var modelContext: ModelContext?
    private let cloudRepo = CloudKitFeedRepository()
    private var localRepo: SwiftDataFeedRepository?
    private var pollTask: Task<Void, Never>?
    private var hasDisplayedCloudList = false
    private var didAttach = false

    var usesSharedCloud: Bool { user != nil }

    func attach(modelContext: ModelContext) {
        guard !didAttach else { return }
        didAttach = true
        self.modelContext = modelContext
        localRepo = SwiftDataFeedRepository(modelContext: modelContext)
        Task { await refreshAccount() }
    }

    func refresh() async {
        if usesSharedCloud {
            await refreshCloud()
        } else {
            await refreshAccount()
        }
    }

    func publish(text: String, imageData: Data?) async throws {
        guard let localRepo else { throw FeedError.saveFailed }
        errorMessage = nil
        var draft = PostDraft(text: text, imageData: imageData)
        if usesSharedCloud {
            draft.authorRecordName = try? await cloudRepo.userRecordName()
        }
        var post = try draft.makePost()
        if usesSharedCloud {
            do {
                post = try await cloudRepo.upload(post)
                post.pendingUpload = false
                try localRepo.upsert(post)
                statusMessage = "Posted"
            } catch {
                post.pendingUpload = true
                try localRepo.upsert(post)
                errorMessage = "Saved on this iPhone. \(error.localizedDescription)"
            }
        } else {
            post.pendingUpload = true
            try localRepo.upsert(post)
            statusMessage = "Saved on this iPhone"
        }
        posts = try await localRepo.fetchPosts()
    }

    private func refreshAccount() async {
        do {
            let status = try await cloudRepo.accountStatus()
            switch status {
            case .available:
                user = ExperienceUser(id: "icloud", displayName: "iCloud")
                statusMessage = "Loading posts from iCloud…"
                startPolling()
                await refreshCloud()
                if let name = try? await cloudRepo.userRecordName() {
                    user = ExperienceUser(id: name, displayName: "iCloud")
                }
            case .noAccount:
                fallBackLocal(status: "Sign into iCloud in Settings to share the feed")
            case .restricted:
                fallBackLocal(status: "iCloud is restricted on this device.", isError: true)
            case .couldNotDetermine:
                fallBackLocal(status: "Couldn’t determine iCloud status. Try again.", isError: true)
            case .temporarilyUnavailable:
                fallBackLocal(status: "iCloud is temporarily unavailable.", isError: true)
            @unknown default:
                fallBackLocal(status: nil)
            }
        } catch {
            fallBackLocal(status: error.localizedDescription, isError: true)
        }
    }

    private func fallBackLocal(status: String?, isError: Bool = false) {
        user = nil
        stopPolling()
        isLoading = false
        if isError {
            errorMessage = status
        } else {
            statusMessage = status
        }
        Task { await refreshLocal() }
    }

    private func refreshCloud() async {
        guard let localRepo else { return }
        if !hasDisplayedCloudList { isLoading = true }
        let flushError = await flushPending()
        do {
            let remote = try await cloudRepo.fetchPosts()
            try localRepo.replaceCache(with: remote)
            posts = try await localRepo.fetchPosts()
            hasDisplayedCloudList = true
            isLoading = false
            statusMessage = "iCloud · \(posts.count) post\(posts.count == 1 ? "" : "s")"
            if let flushError {
                errorMessage = flushError
            }
        } catch {
            isLoading = false
            posts = (try? await localRepo.fetchPosts()) ?? posts
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = message
            if !hasDisplayedCloudList {
                errorMessage = message
            }
        }
    }

    private func flushPending() async -> String? {
        guard let localRepo else { return nil }
        let pending: [Post]
        do {
            pending = try localRepo.pendingPosts()
        } catch {
            return error.localizedDescription
        }
        for var post in pending {
            do {
                post = try await cloudRepo.upload(post)
                post.pendingUpload = false
                try localRepo.upsert(post)
            } catch {
                return error.localizedDescription
            }
        }
        return nil
    }

    private func refreshLocal() async {
        guard let localRepo else { return }
        do {
            posts = try await localRepo.fetchPosts()
            isLoading = false
            if statusMessage == nil || user == nil {
                statusMessage = posts.isEmpty
                    ? "On this iPhone — sign into iCloud to see the shared feed"
                    : "On this iPhone · \(posts.count) post\(posts.count == 1 ? "" : "s")"
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.usesSharedCloud else { continue }
                await self.refreshCloud()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
