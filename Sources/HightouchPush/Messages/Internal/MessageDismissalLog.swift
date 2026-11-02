import Foundation

/// Message ids the host dismissed, so a sync doesn't re-insert them (the server still returns
/// them). Kept in UserDefaults rather than Core Data because the store's recovery path destroys
/// and refetches it. Capped per owner, so very old dismissals can eventually resurface.
struct MessageDismissalLog {

    /// Matches `HightouchMessagesConfig.maxStoredMessages`.
    static let perOwnerLimit = 500

    static let defaultsKey = "com.hightouch.messages.dismissed"

    /// Static because callers create a fresh instance per use.
    private static let lock = NSLock()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func dismissedIds(owner: MessageOwner) -> [String] {
        MessageDismissalLog.lock.lock()
        defer { MessageDismissalLog.lock.unlock() }
        guard let all = defaults.dictionary(forKey: MessageDismissalLog.defaultsKey) as? [String: [String]] else {
            return []
        }
        return all[owner.storageKey] ?? []
    }

    /// A repeat id keeps its original position, so eviction stays by first-dismissal age.
    func record(messageIds: [String], owner: MessageOwner) {
        guard !messageIds.isEmpty else { return }
        MessageDismissalLog.lock.lock()
        defer { MessageDismissalLog.lock.unlock() }

        var all = (defaults.dictionary(forKey: MessageDismissalLog.defaultsKey) as? [String: [String]]) ?? [:]
        var existing = all[owner.storageKey] ?? []
        let known = Set(existing)

        for id in messageIds where !known.contains(id) {
            existing.append(id)
        }

        if existing.count > MessageDismissalLog.perOwnerLimit {
            existing.removeFirst(existing.count - MessageDismissalLog.perOwnerLimit)
        }

        all[owner.storageKey] = existing
        defaults.set(all, forKey: MessageDismissalLog.defaultsKey)
    }

    func clear(owner: MessageOwner? = nil) {
        MessageDismissalLog.lock.lock()
        defer { MessageDismissalLog.lock.unlock() }
        guard let owner = owner else {
            defaults.removeObject(forKey: MessageDismissalLog.defaultsKey)
            return
        }
        guard var all = defaults.dictionary(forKey: MessageDismissalLog.defaultsKey) as? [String: [String]] else {
            return
        }
        all[owner.storageKey] = nil
        defaults.set(all, forKey: MessageDismissalLog.defaultsKey)
    }
}
