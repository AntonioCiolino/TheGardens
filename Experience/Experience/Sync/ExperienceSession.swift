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
    @Published private(set) var messageOfTheDay = AppVoice.seededMessage()
    @Published private(set) var isLoading = true
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    /// All posts known from the cache before moderation filtering is applied.
    private var allPosts: [Post] = []
    /// Per-device blocked authors and hidden posts. Injected so the UI can share the same instance.
    private let moderation: ModerationStore
    /// Report tally per post id, used for automatic threshold hiding.
    private var reportCounts: [UUID: Int] = [:]
    /// The shared moderator roster.
    private var roster = ModeratorRoster()
    /// This device's CloudKit user record name, once known.
    @Published private(set) var currentUserRecordName: String?
    /// True when the signed-in guest is a moderator and may take posts down.
    @Published private(set) var isModerator = false

    /// Keeps GardensCore linked for a later plant screen.
    let sharedPlantDomain = PlantDomainLink.moduleName

    private var modelContext: ModelContext?
    private let cloudRepo = CloudKitFeedRepository()
    private var localRepo: SwiftDataFeedRepository?
    private var pollTask: Task<Void, Never>?
    private var hasDisplayedCloudList = false
    private var didAttach = false

    init(moderation: ModerationStore) {
        self.moderation = moderation
    }

    var usesSharedCloud: Bool { user != nil }

    /// Applies the current block/hide choices to the cached posts and republishes `posts`.
    /// Posts at or over the report threshold are hidden for everyone except moderators,
    /// who keep seeing them so they can remove or keep them.
    private func applyModeration() {
        posts = allPosts.filter { post in
            if moderation.isHidden(postID: post.id) { return false }
            if moderation.isBlocked(authorRecordName: post.authorRecordName) { return false }
            if !isModerator, reportCount(for: post) >= ModerationPolicy.autoHideReportThreshold {
                return false
            }
            return true
        }
    }

    /// Reports accumulated for a post across all guests.
    func reportCount(for post: Post) -> Int {
        reportCounts[post.id] ?? 0
    }

    /// True when a post is being shown to a moderator only because it is over the report threshold.
    func isAwaitingReview(_ post: Post) -> Bool {
        isModerator && reportCount(for: post) >= ModerationPolicy.autoHideReportThreshold
    }

    /// Posts currently over the report threshold, newest first — the moderator review queue.
    var flaggedPosts: [Post] {
        guard isModerator else { return [] }
        return allPosts
            .filter { reportCount(for: $0) >= ModerationPolicy.autoHideReportThreshold }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// The current moderator roster, sorted for display.
    var moderatorRecordNames: [String] {
        roster.recordNames.sorted()
    }

    /// Reports a post to the shared feed and immediately hides it on this device.
    func report(_ post: Post, reason: ReportReason) async {
        moderation.hide(postID: post.id)
        applyModeration()
        let report = FeedReport(
            postID: post.id,
            authorRecordName: post.authorRecordName,
            reason: reason
        )
        do {
            try await cloudRepo.submitReport(report)
            statusMessage = "Thanks — we’ll review this within 24 hours."
        } catch {
            // The post stays hidden locally even if the report upload fails.
            statusMessage = "Hidden on this iPhone. We’ll review it when iCloud reconnects."
        }
    }

    /// Blocks a post's author so none of their posts appear on this device, and reports the post.
    func block(_ post: Post) async {
        moderation.block(authorRecordName: post.authorRecordName)
        moderation.hide(postID: post.id)
        applyModeration()
        statusMessage = "You won’t see posts from this person anymore."
    }

    /// Operator takedown. Hard-deletes the post from the shared feed for every guest.
    /// Only has effect for moderators; the UI only exposes it to them.
    func removePost(_ post: Post) async {
        guard isModerator else { return }
        do {
            try await cloudRepo.deletePost(id: post.id)
            allPosts.removeAll { $0.id == post.id }
            applyModeration()
            statusMessage = "Removed from the feed."
        } catch {
            errorMessage = "Couldn’t remove the post: \(error.localizedDescription)"
        }
    }

    /// Operator "keep": clears every report against a post so it drops below the auto-hide
    /// threshold and returns to the public feed. The post itself is left in place.
    /// Only has effect for moderators; the UI only exposes it to them.
    func reinstate(_ post: Post) async {
        guard isModerator else { return }
        do {
            try await cloudRepo.clearReports(forPostID: post.id)
            reportCounts[post.id] = 0
            moderation.unhide(postID: post.id)
            applyModeration()
            statusMessage = "Reinstated to the feed."
        } catch {
            errorMessage = "Couldn’t reinstate the post: \(error.localizedDescription)"
        }
    }

    /// Adds another guest as a moderator by their CloudKit user record name.
    func promoteModerator(userRecordName: String) async {
        guard isModerator else { return }
        do {
            roster = try await cloudRepo.addModerator(userRecordName: userRecordName)
            statusMessage = "Added a moderator."
        } catch {
            errorMessage = "Couldn’t add the moderator: \(error.localizedDescription)"
        }
    }

    /// Loads the report tally and moderator roster, then recomputes moderator status.
    /// If the roster is empty (fresh install, no seeds), the current guest bootstraps as
    /// the first moderator so the garden is never left without one.
    private func refreshModerationState() async {
        reportCounts = (try? await cloudRepo.fetchReportCounts()) ?? reportCounts
        if let loaded = try? await cloudRepo.fetchOrSeedModerators() {
            roster = loaded
        }
        if roster.isEmpty, let me = currentUserRecordName, !me.isEmpty {
            roster = (try? await cloudRepo.addModerator(userRecordName: me)) ?? roster
        }
        isModerator = roster.contains(currentUserRecordName)
    }

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

    func publish(text: String, imageData: Data?, authorName: String = "") async throws {
        guard let localRepo else { throw FeedError.saveFailed }
        errorMessage = nil
        var draft = PostDraft(text: text, imageData: imageData, authorName: authorName)
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
        allPosts = try await localRepo.fetchPosts()
        applyModeration()
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
                    currentUserRecordName = name
                    await refreshModerationState()
                    applyModeration()
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
            try localRepo.replaceCache(with: remote.filter(Self.isGuestPost))
            allPosts = try await localRepo.fetchPosts()
            applyModeration()
            await refreshMessageOfTheDay()
            hasDisplayedCloudList = true
            isLoading = false
            if currentUserRecordName != nil {
                reportCounts = (try? await cloudRepo.fetchReportCounts()) ?? reportCounts
                applyModeration()
            }
            statusMessage = "iCloud · \(posts.count) post\(posts.count == 1 ? "" : "s")"
            errorMessage = flushError
        } catch {
            isLoading = false
            allPosts = (try? await localRepo.fetchPosts())?.filter(Self.isGuestPost) ?? allPosts
            applyModeration()
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if hasDisplayedCloudList {
                // We already have posts on screen; show the hiccup once as a quiet status line.
                statusMessage = message
                errorMessage = nil
            } else {
                // Nothing shown yet; surface it once as the error line.
                statusMessage = nil
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

    func refreshMessageOfTheDay() async {
        if let saved = UserDefaults.standard.string(forKey: Self.messageCacheKey),
           !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var note = AppVoice.seededMessage()
            note.text = saved
            messageOfTheDay = note
        }
        guard usesSharedCloud else { return }
        do {
            let remote = try await cloudRepo.fetchOrSeedMessageOfTheDay()
            messageOfTheDay = remote
            UserDefaults.standard.set(remote.text, forKey: Self.messageCacheKey)
        } catch {
            // The seeded note stays on screen when iCloud has no message yet.
        }
    }

    private static func isGuestPost(_ post: Post) -> Bool {
        post.authorRecordName != AppVoice.recordName && post.id != AppVoice.messageID
    }

    private static let messageCacheKey = "experience.messageOfTheDay"

    private func refreshLocal() async {
        guard let localRepo else { return }
        do {
            allPosts = try await localRepo.fetchPosts().filter(Self.isGuestPost)
            applyModeration()
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
