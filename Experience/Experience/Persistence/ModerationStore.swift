import Foundation

/// Local record of which authors a guest has blocked and which posts they have hidden.
///
/// Blocking and hiding are per-device choices stored in `UserDefaults`, so they take effect
/// instantly and survive relaunch without waiting on iCloud. The shared feed is filtered
/// against these sets in `ExperienceSession`.
@MainActor
final class ModerationStore: ObservableObject {
    @Published private(set) var blockedAuthors: Set<String> = []
    @Published private(set) var hiddenPostIDs: Set<UUID> = []

    private let defaults: UserDefaults
    private static let blockedKey = "experience.blockedAuthors"
    private static let hiddenKey = "experience.hiddenPosts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let authors = defaults.array(forKey: Self.blockedKey) as? [String] {
            blockedAuthors = Set(authors)
        }
        if let ids = defaults.array(forKey: Self.hiddenKey) as? [String] {
            hiddenPostIDs = Set(ids.compactMap(UUID.init(uuidString:)))
        }
    }

    func isBlocked(authorRecordName: String?) -> Bool {
        guard let name = authorRecordName, !name.isEmpty else { return false }
        return blockedAuthors.contains(name)
    }

    func isHidden(postID: UUID) -> Bool {
        hiddenPostIDs.contains(postID)
    }

    /// Hide every post from this author and remember the choice.
    func block(authorRecordName: String?) {
        guard let name = authorRecordName, !name.isEmpty else { return }
        blockedAuthors.insert(name)
        persistBlocked()
    }

    func unblock(authorRecordName: String) {
        blockedAuthors.remove(authorRecordName)
        persistBlocked()
    }

    /// Hide a single post on this device (used right after a report so the guest stops seeing it).
    func hide(postID: UUID) {
        hiddenPostIDs.insert(postID)
        persistHidden()
    }

    /// Un-hide a single post on this device (used when a moderator reinstates a reported post).
    func unhide(postID: UUID) {
        hiddenPostIDs.remove(postID)
        persistHidden()
    }

    private func persistBlocked() {
        defaults.set(Array(blockedAuthors), forKey: Self.blockedKey)
    }

    private func persistHidden() {
        defaults.set(hiddenPostIDs.map(\.uuidString), forKey: Self.hiddenKey)
    }
}
