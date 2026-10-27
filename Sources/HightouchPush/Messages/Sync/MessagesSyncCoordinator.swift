import Foundation
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

/// Fetches messages and reconciles them into the store. Cooldown and coalescing are per owner: a
/// sync for a different owner than the one in flight is queued behind it, not joined to it. So is a
/// forced sync for the same owner, since the in-flight response may predate whatever forced it.
final class MessagesSyncCoordinator {
    typealias Completion = (Result<HightouchMessagesChange, Error>) -> Void

    static let minCooldown: TimeInterval = 60

    static let lastSyncedAtDefaultsKey = "com.hightouch.messages.lastSyncedAt"

    static let lastSyncedOwnerDefaultsKey = "com.hightouch.messages.lastSyncedOwner"

    /// Jittered so clients hitting a struggling server don't retry in lockstep.
    private static let retryDelayRange: ClosedRange<TimeInterval> = 0.05...0.25

    private let analytics: Analytics
    private let config: HightouchMessagesConfig
    private let store: MessageStore
    private let client: MessagesHTTPClient
    private let userDefaults: UserDefaults

    private let ownerProvider: (Analytics) -> MessageOwner?

    private let deviceTokenProvider: () -> String?

    private let stateQueue = DispatchQueue(label: "com.hightouch.messages.sync.coordinator")
    private var inFlightOwner: MessageOwner?
    private var inFlightCompletions: [Completion] = []
    /// Re-resolves the owner when it starts.
    private var queuedFollowUp: (force: Bool, updatesCooldown: Bool, completions: [Completion])?

    init(
        analytics: Analytics,
        config: HightouchMessagesConfig,
        store: MessageStore,
        client: MessagesHTTPClient? = nil,
        userDefaults: UserDefaults = .standard,
        ownerProvider: @escaping (Analytics) -> MessageOwner? = MessageOwner.current,
        deviceTokenProvider: @escaping () -> String? = { HightouchPush.deviceTokenHex }
    ) {
        self.analytics = analytics
        self.config = config
        self.store = store
        self.client = client ?? MessagesHTTPClient(
            analytics: analytics, config: config, requestFactory: config.requestFactory
        )
        self.userDefaults = userDefaults
        self.ownerProvider = ownerProvider
        self.deviceTokenProvider = deviceTokenProvider
    }

    static func shouldSync(lastSyncedAt: TimeInterval, now: TimeInterval, cooldown: TimeInterval, force: Bool) -> Bool {
        if force { return true }
        return (now - lastSyncedAt) >= max(cooldown, minCooldown)
    }

    /// `completion` always runs on the main queue. Skipped syncs report an empty success.
    /// `updatesCooldown: false` leaves the cooldown unstamped, for a sync whose response may be
    /// incomplete (see `HightouchMessages.identityDidChange()`).
    func sync(force: Bool, updatesCooldown: Bool = true, completion: Completion?) {
        stateQueue.async {
            self.begin(force: force, updatesCooldown: updatesCooldown, completions: completion.map { [$0] } ?? [])
        }
    }

    /// Must be called on `stateQueue`.
    private func begin(force: Bool, updatesCooldown: Bool, completions: [Completion]) {
        // The gateway always answers an anonymous id with an empty inbox.
        guard let owner = ownerProvider(analytics), owner.kind == .userId else {
            deliver(.success(HightouchMessagesChange()), to: completions)
            return
        }

        if let inFlightOwner = inFlightOwner {
            if inFlightOwner == owner && !force {
                inFlightCompletions += completions
            } else {
                let pending = queuedFollowUp
                queuedFollowUp = (force: force || (pending?.force ?? false),
                                  updatesCooldown: updatesCooldown && (pending?.updatesCooldown ?? true),
                                  completions: (pending?.completions ?? []) + completions)
            }
            return
        }

        let lastSyncedAt = userDefaults.string(forKey: MessagesSyncCoordinator.lastSyncedOwnerDefaultsKey) == owner.storageKey
            ? userDefaults.double(forKey: MessagesSyncCoordinator.lastSyncedAtDefaultsKey)
            : 0
        guard MessagesSyncCoordinator.shouldSync(
            lastSyncedAt: lastSyncedAt,
            now: Date().timeIntervalSince1970,
            cooldown: config.foregroundSyncCooldown,
            force: force
        ) else {
            deliver(.success(HightouchMessagesChange()), to: completions)
            return
        }

        // The gateway requires a registered device token.
        guard let deviceToken = deviceTokenProvider(), !deviceToken.isEmpty else {
            deliver(.success(HightouchMessagesChange()), to: completions)
            return
        }

        inFlightOwner = owner
        inFlightCompletions = completions
        performFetch(owner: owner, deviceToken: deviceToken, updatesCooldown: updatesCooldown, retriesRemaining: 1)
    }

    private func performFetch(owner: MessageOwner, deviceToken: String, updatesCooldown: Bool, retriesRemaining: Int) {
        client.fetchMessages(owner: owner, deviceToken: deviceToken) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                self.handleFetchSuccess(response, owner: owner, updatesCooldown: updatesCooldown)
            case .failure(let error):
                if retriesRemaining > 0, MessagesSyncCoordinator.isRetryable(error) {
                    let delay = TimeInterval.random(in: MessagesSyncCoordinator.retryDelayRange)
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.performFetch(
                            owner: owner, deviceToken: deviceToken,
                            updatesCooldown: updatesCooldown, retriesRemaining: retriesRemaining - 1
                        )
                    }
                } else {
                    self.analytics.reportInternalError(error)
                    self.finish(.failure(error))
                }
            }
        }
    }

    /// 5xx and transport failures retry once; a 4xx won't succeed on repeat.
    private static func isRetryable(_ error: Error) -> Bool {
        if let httpError = error as? MessagesHTTPClientError, case .statusCode(let code) = httpError {
            return code >= 500
        }
        return true
    }

    /// Each store call is a `perform` on the same serial context, so they run in order.
    private func handleFetchSuccess(_ response: MessagesFetchResponse, owner: MessageOwner, updatesCooldown: Bool) {
        if response.malformedCount > 0 {
            analytics.reportInternalError(MalformedMessagesError(count: response.malformedCount))
        }

        // The server still returns dismissed messages; a closure so the log is read on the write
        // queue (see `replaceAll`).
        store.replaceAll(response.messages, owner: owner, limit: config.maxStoredMessages, suppressing: {
            HightouchMessages.dismissedIds(owner: owner)
        }) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let outcome):
                self.store.pruneExpired()
                // `owner` already fits under the cap (see `replaceAll`'s limit), so only other
                // owners' rows are evicted and every change to `owner` is in `outcome`.
                self.store.enforceLimit(maxStoredMessages: self.config.maxStoredMessages, preserving: owner) { _ in
                    if updatesCooldown {
                        self.userDefaults.set(Date().timeIntervalSince1970, forKey: MessagesSyncCoordinator.lastSyncedAtDefaultsKey)
                        self.userDefaults.set(owner.storageKey, forKey: MessagesSyncCoordinator.lastSyncedOwnerDefaultsKey)
                    }

                    let change = HightouchMessagesChange(
                        insertedIds: outcome.insertedIds,
                        updatedIds: outcome.updatedIds,
                        removedIds: outcome.removedIds
                    )
                    if !change.insertedIds.isEmpty || !change.updatedIds.isEmpty || !change.removedIds.isEmpty {
                        HightouchMessages.notifyChange(change)
                    }
                    self.finish(.success(change))
                }
            case .failure(let error):
                self.analytics.reportInternalError(error)
                self.finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<HightouchMessagesChange, Error>) {
        stateQueue.async {
            let completions = self.inFlightCompletions
            self.inFlightCompletions = []
            self.inFlightOwner = nil
            self.deliver(result, to: completions)

            if let followUp = self.queuedFollowUp {
                self.queuedFollowUp = nil
                self.begin(force: followUp.force, updatesCooldown: followUp.updatesCooldown, completions: followUp.completions)
            }
        }
    }

    private func deliver(_ result: Result<HightouchMessagesChange, Error>, to completions: [Completion]) {
        guard !completions.isEmpty else { return }
        DispatchQueue.main.async {
            for completion in completions {
                completion(result)
            }
        }
    }
}
#endif
