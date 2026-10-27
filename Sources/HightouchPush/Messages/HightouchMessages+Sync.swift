import Foundation
import Hightouch

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#endif

/// The result of a `HightouchMessages.sync(...)` call. `messageCount` is inserted + updated +
/// removed.
public enum HightouchSyncOutcome {
    case changed(messageCount: Int)
    case unchanged
    case failed(Error)
}

extension HightouchMessages {

    /// Fetches the latest messages from the server and reconciles the local cache.
    ///
    /// Completes with `.unchanged` and makes no network call when there's no user, no store, or no
    /// registered APNs token. `completion` is delivered on the main queue. `force: true` bypasses
    /// `HightouchMessagesConfig.foregroundSyncCooldown`.
    public static func sync(force: Bool = false, completion: ((HightouchSyncOutcome) -> Void)? = nil) {
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        syncInternal(force: force, completion: completion)
        #else
        if let completion = completion {
            DispatchQueue.main.async { completion(.unchanged) }
        }
        #endif
    }

    static func syncIfStale() {
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        syncInternal(force: false, completion: nil)
        #endif
    }

    /// Not forced: the cooldown is per user, so a new identity syncs immediately. The gateway only
    /// answers once it has linked the device token to the new user, which happens asynchronously
    /// after the token re-registration, so this sync doesn't stamp the cooldown: an early, empty
    /// response mustn't hold off the next foreground sync.
    static func identityDidChange() {
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        #if DEBUG
        if Analytics.isRunningUnitTests { return }
        #endif
        syncInternal(force: false, updatesCooldown: false, completion: nil)
        #endif
    }

    /// Forced, because launch is the only reconcile point for an app that was force-quit when a
    /// ghost push arrived.
    static func syncOnInitialize() {
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        #if DEBUG
        // Skip the live request under unit tests, like the core SDK's settings fetch does.
        if Analytics.isRunningUnitTests { return }
        #endif
        syncInternal(force: true, completion: nil)
        #endif
    }

    #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))

    private static let syncStateQueue = DispatchQueue(label: "com.hightouch.messages.sync.facade")

    private static var _syncCoordinator: MessagesSyncCoordinator?

    /// A nil `store` (failed to open) clears the coordinator, so syncs become no-ops.
    static func configureMessagesSyncCoordinator(analytics: Analytics, config: HightouchMessagesConfig, store: MessageStore?) {
        syncStateQueue.sync {
            guard let store = store else {
                _syncCoordinator = nil
                return
            }
            _syncCoordinator = MessagesSyncCoordinator(analytics: analytics, config: config, store: store)
        }
    }

    /// Test seam.
    static func resetMessagesSyncStateForTesting() {
        syncStateQueue.sync { _syncCoordinator = nil }
        #if os(iOS) || targetEnvironment(macCatalyst)
        if let token = foregroundSyncObserverToken {
            NotificationCenter.default.removeObserver(token)
            foregroundSyncObserverToken = nil
        }
        #endif
    }

    #if os(iOS) || targetEnvironment(macCatalyst)
    private static var foregroundSyncObserverToken: NSObjectProtocol?

    /// Test seam.
    static var isMessagesForegroundObserverRegistered: Bool {
        syncStateQueue.sync { foregroundSyncObserverToken != nil }
    }

    /// Tears down any existing observer first, so re-initializing with `syncOnForeground: false`
    /// actually removes it.
    static func configureMessagesForegroundSync(config: HightouchMessagesConfig) {
        syncStateQueue.sync {
            if let token = foregroundSyncObserverToken {
                NotificationCenter.default.removeObserver(token)
                foregroundSyncObserverToken = nil
            }
        }
        guard config.syncOnForeground else { return }
        let token = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            HightouchMessages.syncIfStale()
        }
        syncStateQueue.sync { foregroundSyncObserverToken = token }
    }
    #else
    static func configureMessagesForegroundSync(config: HightouchMessagesConfig) {}
    #endif

    /// Queued behind any pending store open, so a sync requested right after `initialize` (e.g. by
    /// a ghost push that launched the app) isn't dropped for want of a coordinator.
    private static func syncInternal(
        force: Bool,
        updatesCooldown: Bool = true,
        completion: ((HightouchSyncOutcome) -> Void)?
    ) {
        setupQueue.async {
            syncWithCurrentCoordinator(force: force, updatesCooldown: updatesCooldown, completion: completion)
        }
    }

    private static func syncWithCurrentCoordinator(
        force: Bool,
        updatesCooldown: Bool,
        completion: ((HightouchSyncOutcome) -> Void)?
    ) {
        guard let coordinator = syncStateQueue.sync(execute: { _syncCoordinator }) else {
            if let completion = completion {
                DispatchQueue.main.async { completion(.unchanged) }
            }
            return
        }

        coordinator.sync(force: force, updatesCooldown: updatesCooldown) { result in
            let outcome: HightouchSyncOutcome
            switch result {
            case .success(let change):
                if change.insertedIds.isEmpty && change.updatedIds.isEmpty && change.removedIds.isEmpty {
                    outcome = .unchanged
                } else {
                    outcome = .changed(
                        messageCount: change.insertedIds.count + change.updatedIds.count + change.removedIds.count
                    )
                }
            case .failure(let error):
                outcome = .failed(error)
            }
            if let completion = completion {
                DispatchQueue.main.async { completion(outcome) }
            }
        }
    }

    #endif
}
