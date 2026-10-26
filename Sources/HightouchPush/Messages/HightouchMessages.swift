import Foundation
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData
#endif

/// Public facade for embedded messages. On platforms without the Core Data store (Linux, tvOS,
/// watchOS) every method is a no-op returning empty results.
public final class HightouchMessages {
    private init() {}

    // Unlike `HightouchPush`, state here is guarded: a ghost push can sync on an APNs background
    // thread while the host's main thread is querying.
    private static let stateQueue = DispatchQueue(label: "com.hightouch.messages.facade")

    private static let queryQueue = DispatchQueue(label: "com.hightouch.messages.query")

    /// Key for the `HightouchMessagesChange` in `.hightouchMessagesDidChange`'s `userInfo`.
    public static let changeUserInfoKey = "com.hightouch.messages.change"

    private static var _analytics: Analytics?
    private static var _config: HightouchMessagesConfig?

    #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
    private static var _store: MessageStore?
    private static var _storeURL: URL?

    /// Test seam: overrides where the store is opened. `nil` means `.appContainer`.
    static var testStoreLocation: MessageStore.Location?

    /// Test seam.
    static var openStoreIdentityForTesting: ObjectIdentifier? {
        stateQueue.sync { _store.map(ObjectIdentifier.init) }
    }
    #endif

    /// Test seam: resets all static state to "never initialized".
    static func resetForTesting() {
        MessageDismissalLog().clear()
        stateQueue.sync {
            _analytics = nil
            _config = nil
            #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
            _store = nil
            _storeURL = nil
            testStoreLocation = nil
            #endif
        }
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        resetMessagesSyncStateForTesting()
        #endif
    }

    /// Whether messages are enabled. `true` even if the store failed to open; queries then return empty.
    public static var isInitialized: Bool {
        stateQueue.sync { _analytics != nil }
    }

    /// Called by `HightouchPush.initialize(...)` when `HightouchPushConfig.messages` is set.
    static func initialize(analytics: Analytics, config: HightouchMessagesConfig) {
        stateQueue.sync {
            _analytics = analytics
            _config = config

            #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
            openStoreIfNeeded(analytics: analytics, config: config)
            // The launch sync runs after this lock is released; starting it inside would deadlock.
            configureMessagesForegroundSync(config: config)
            configureMessagesSyncCoordinator(analytics: analytics, config: config, store: _store)
            #endif
        }

        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        if config.syncOnLaunch { syncOnInitialize() }
        #endif
    }

    #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
    /// Keyed on the resolved store URL so repeated initialization never opens two stores over one
    /// SQLite file. Must be called on `stateQueue`.
    private static func openStoreIfNeeded(analytics: Analytics, config: HightouchMessagesConfig) {
        let writeKey = config.writeKeyOverride ?? analytics.writeKey
        let location = testStoreLocation ?? .appContainer
        let resolvedURL = try? MessageStoreLocation.storeURL(
            for: location, writeKey: writeKey, modelVersion: MessageStoreSchema.modelVersion
        )

        if _store != nil, let resolvedURL = resolvedURL, resolvedURL == _storeURL {
            return
        }

        do {
            let store = try MessageStore(writeKey: writeKey, location: location)
            _store = store
            _storeURL = resolvedURL
            store.pruneExpired()
        } catch {
            _store = nil
            _storeURL = nil
            analytics.reportInternalError(error)
        }
    }

    private static func currentStoreAndOwner() -> (MessageStore, MessageOwner)? {
        let (analytics, store) = stateQueue.sync { (_analytics, _store) }
        guard let analytics = analytics, let store = store else { return nil }
        guard let owner = MessageOwner.current(analytics: analytics) else { return nil }
        return (store, owner)
    }
    #endif

    /// Returns cached messages matching `query` for the current user. Reading doesn't remove
    /// anything; a message stays until it's dismissed, expires or the server stops returning it.
    public static func messages(matching query: HightouchMessageQuery) -> [HightouchMessage] {
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        guard let (store, owner) = currentStoreAndOwner() else { return [] }
        return store.messages(matching: query, owner: owner)
        #else
        return []
        #endif
    }

    public static func messages(
        locationId: String? = nil,
        variantSlug: String? = nil,
        limit: Int? = nil
    ) -> [HightouchMessage] {
        return messages(matching: HightouchMessageQuery(locationId: locationId, variantSlug: variantSlug, limit: limit))
    }

    /// Returns the cached message with the given id for the current user.
    public static func message(withId messageId: String) -> HightouchMessage? {
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        guard let (store, owner) = currentStoreAndOwner() else { return nil }
        return store.message(withId: messageId, owner: owner)
        #else
        return nil
        #endif
    }

    /// Number of cached messages matching `query` for the current user.
    public static func messageCount(matching query: HightouchMessageQuery) -> Int {
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        guard let (store, owner) = currentStoreAndOwner() else { return 0 }
        return store.count(matching: query, owner: owner)
        #else
        return 0
        #endif
    }

    /// Same as `messages(matching:)`, but fetches off the calling thread and completes on the main
    /// queue.
    public static func loadMessages(
        matching query: HightouchMessageQuery,
        completion: @escaping ([HightouchMessage]) -> Void
    ) {
        queryQueue.async {
            let result = messages(matching: query)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// `async` counterpart to `loadMessages(matching:completion:)`.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public static func loadMessages(matching query: HightouchMessageQuery) async -> [HightouchMessage] {
        return await withCheckedContinuation { continuation in
            loadMessages(matching: query) { continuation.resume(returning: $0) }
        }
    }

    #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
    // Records before deleting: the delete is asynchronous, and the record is what stops a racing
    // sync from re-inserting the row.
    static func removeDismissed(messageId: String) {
        guard let (store, owner) = currentStoreAndOwner() else { return }
        guard store.message(withId: messageId, owner: owner) != nil else { return }
        MessageDismissalLog().record(messageIds: [messageId], owner: owner)
        store.delete(messageId: messageId, owner: owner) { removed in
            if removed > 0 {
                notifyChange(HightouchMessagesChange(insertedIds: [], updatedIds: [], removedIds: [messageId]))
            }
        }
    }

    static func dismissedIds(owner: MessageOwner) -> Set<String> {
        Set(MessageDismissalLog().dismissedIds(owner: owner))
    }
    #endif

    /// Discards the current user's cached messages and forgets which were dismissed, so the next sync
    /// repopulates from the server. Completes on the main queue with the number discarded.
    public static func clearCachedMessages(completion: ((Int) -> Void)? = nil) {
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        guard let (store, owner) = currentStoreAndOwner() else {
            DispatchQueue.main.async { completion?(0) }
            return
        }
        MessageDismissalLog().clear(owner: owner)
        store.deleteAll(owner: owner) { removedIds in
            if !removedIds.isEmpty {
                notifyChange(HightouchMessagesChange(insertedIds: [], updatedIds: [], removedIds: removedIds))
            }
            DispatchQueue.main.async { completion?(removedIds.count) }
        }
        #else
        DispatchQueue.main.async { completion?(0) }
        #endif
    }

    /// Like `clearCachedMessages()`, but for every user that has synced on this device. Intended for
    /// debug tooling.
    public static func clearAllCachedMessagesForAllUsers(completion: ((Int) -> Void)? = nil) {
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        guard let store = stateQueue.sync(execute: { _store }) else {
            DispatchQueue.main.async { completion?(0) }
            return
        }
        MessageDismissalLog().clear()
        store.deleteAllOwners { removedIds in
            if !removedIds.isEmpty {
                notifyChange(HightouchMessagesChange(insertedIds: [], updatedIds: [], removedIds: removedIds))
            }
            DispatchQueue.main.async { completion?(removedIds.count) }
        }
        #else
        DispatchQueue.main.async { completion?(0) }
        #endif
    }

    /// Removes one cached message for the current user, without a network call. Completes on the
    /// main queue with whether a row was removed.
    public static func deleteMessage(withId messageId: String, completion: ((Bool) -> Void)? = nil) {
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        guard let (store, owner) = currentStoreAndOwner() else {
            DispatchQueue.main.async { completion?(false) }
            return
        }
        store.delete(messageId: messageId, owner: owner) { removed in
            if removed > 0 {
                notifyChange(HightouchMessagesChange(insertedIds: [], updatedIds: [], removedIds: [messageId]))
            }
            DispatchQueue.main.async { completion?(removed > 0) }
        }
        #else
        DispatchQueue.main.async { completion?(false) }
        #endif
    }

    /// Posts the delegate callback and `.hightouchMessagesDidChange` on the main queue.
    static func notifyChange(_ change: HightouchMessagesChange) {
        let delegate = stateQueue.sync { _config?.delegate }
        DispatchQueue.main.async {
            delegate?.hightouchMessagesDidChange(change)
            NotificationCenter.default.post(
                name: .hightouchMessagesDidChange,
                object: nil,
                userInfo: [changeUserInfoKey: change]
            )
        }
    }
}
