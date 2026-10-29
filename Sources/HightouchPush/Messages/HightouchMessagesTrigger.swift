#if os(iOS) || targetEnvironment(macCatalyst)

import Foundation
import UIKit
import Hightouch

/// Executes a ghost-push command and resolves the OS's `UIBackgroundFetchResult`.
enum HightouchMessagesTrigger {

    /// Kept under the OS's ~30s silent-push allowance: overrunning it gets the process killed and
    /// reduces the app's future background-execution budget.
    static let selfImposedDeadline: TimeInterval = 20

    private static func defaultSync(_ command: HTMessageCommand) async -> HightouchSyncOutcome {
        await withCheckedContinuation { continuation in
            HightouchMessages.sync(force: true) { outcome in
                continuation.resume(returning: outcome)
            }
        }
    }

    /// `isInitialized`, `deadline` and `sync` are test seams.
    static func handle(
        userInfo: [AnyHashable: Any],
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
        isInitialized: @autoclosure () -> Bool = HightouchPush.isInitialized,
        deadline: TimeInterval = HightouchMessagesTrigger.selfImposedDeadline,
        sync: @escaping (HTMessageCommand) async -> HightouchSyncOutcome = HightouchMessagesTrigger.defaultSync
    ) {
        guard let command = HTMessageCommand(userInfo) else {
            // Silent: every non-Hightouch push takes this path too.
            completionHandler(.noData)
            return
        }

        // A background launch can deliver a push before the host calls `initialize()`.
        guard isInitialized() else {
            print("[HightouchPush] Ignoring '\(command.verb.rawValue)' command: HightouchPush.initialize() has not run. "
                  + "Call it synchronously in application(_:didFinishLaunchingWithOptions:) — iOS can deliver a "
                  + "background push moments after launch, including into a background-launched process.")
            completionHandler(.noData)
            return
        }

        if !HightouchMessages.isInitialized {
            print("[HightouchPush] '\(command.verb.rawValue)' command received, but embedded messages are not enabled, "
                  + "so it will have no effect. Set HightouchPushConfig.messages before calling initialize().")
        }

        // In the foreground there's no OS budget to protect, so skip the background task and flush.
        let isForeground = UIApplication.shared.applicationState == .active
        let completion = TriggerCompletion(
            isForeground: isForeground,
            completionHandler: completionHandler,
            emitDelivered: { emitDeliveredEvent(command: command, messageCount: $0) }
        )
        completion.beginBackgroundTaskIfNeeded()

        // `.noData`, not `.failed`: running out of time isn't a failed fetch, and `.failed` counts
        // against future background delivery. The sync keeps going; its result is just not reported.
        if deadline > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + deadline) {
                completion.complete(.noData, messageCount: 0)
            }
        }

        // A push can carry both a command and customData; this path owns the single completion handler.
        let customData = HTPushPayload(userInfo)?.customData

        Task {
            let (result, messageCount) = await execute(command: command, sync: sync)

            if let customData = customData, !customData.isEmpty,
               let delegate = HightouchPush.silentPushDelegate {
                await delegate.receive(customData: customData)
            }

            completion.complete(result, messageCount: messageCount)
        }
    }

    private static func execute(
        command: HTMessageCommand,
        sync: @escaping (HTMessageCommand) async -> HightouchSyncOutcome
    ) async -> (UIBackgroundFetchResult, Int) {
        switch command.verb {
        case .syncMessages:
            return mapOutcome(await sync(command))
        }
    }

    private static func mapOutcome(_ outcome: HightouchSyncOutcome) -> (UIBackgroundFetchResult, Int) {
        switch outcome {
        case .changed(let messageCount):
            return (.newData, messageCount)
        case .unchanged:
            return (.noData, 0)
        case .failed:
            return (.failed, 0)
        }
    }

    private static func emitDeliveredEvent(command: HTMessageCommand, messageCount: Int) {
        var properties: [String: Any] = [
            "provider_event_type": CepEventTracking.pushDelivered,
            "sync_reason": command.verb.rawValue,
            "message_count": messageCount,
        ]

        // Omitted rather than `as Any`, which would encode a nil Optional as JSON null.
        if let pushMessageId = command.pushMessageId {
            properties["push_message_id"] = pushMessageId
        }
        if let reason = command.reason {
            properties["reason"] = reason
        }
        if let messageIds = command.messageIds {
            properties["message_ids"] = messageIds
        }
        if let locationIds = command.locationIds {
            properties["location_ids"] = locationIds
        }
        if let syncToken = command.syncToken {
            properties["sync_token"] = syncToken
        }

        CepEventTracking.track(
            name: CepEventTracking.engagementEvents,
            properties: properties,
            messageContext: command.messageContext ?? [:],
            channel: .push
        )
    }
}

/// Ensures the completion handler runs once across success, the deadline and background-task
/// expiration. Calling it twice crashes on some iOS versions. Whichever path wins also emits the
/// `delivered` event, before the flush, so it isn't left queued in a process about to be suspended.
private final class TriggerCompletion {
    private let lock = NSLock()
    private var completionHandler: ((UIBackgroundFetchResult) -> Void)?
    private let emitDelivered: (Int) -> Void
    private let isForeground: Bool
    /// Main queue only.
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    init(
        isForeground: Bool,
        completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
        emitDelivered: @escaping (Int) -> Void
    ) {
        self.isForeground = isForeground
        self.completionHandler = completionHandler
        self.emitDelivered = emitDelivered
    }

    func beginBackgroundTaskIfNeeded() {
        guard !isForeground else { return }
        // The expiration handler runs on main, and the task must be ended before it returns or the
        // watchdog kills the app; `complete` finishes synchronously when already on main.
        backgroundTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.complete(.noData, messageCount: 0)
        }
    }

    func complete(_ result: UIBackgroundFetchResult, messageCount: Int) {
        lock.lock()
        guard let handler = completionHandler else {
            lock.unlock()
            return
        }
        completionHandler = nil
        lock.unlock()

        if Thread.isMainThread {
            finish(handler, result: result, messageCount: messageCount)
        } else {
            DispatchQueue.main.async {
                self.finish(handler, result: result, messageCount: messageCount)
            }
        }
    }

    private func finish(_ handler: (UIBackgroundFetchResult) -> Void, result: UIBackgroundFetchResult, messageCount: Int) {
        emitDelivered(messageCount)

        // A process launched directly into the background never posts didEnterBackground, so the
        // normal flush never runs and the `delivered` event would sit in the queue.
        if !isForeground {
            HightouchPush.analytics.flush()
        }

        handler(result)

        if backgroundTaskId != .invalid {
            let taskId = backgroundTaskId
            backgroundTaskId = .invalid
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }
}

#endif
