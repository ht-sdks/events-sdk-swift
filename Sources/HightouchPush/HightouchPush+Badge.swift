#if os(iOS) || targetEnvironment(macCatalyst)

import Foundation
import UIKit
import UserNotifications

extension HightouchPush {

    private static var foregroundObserverToken: NSObjectProtocol?

    /// Set the application icon badge to `count`. Negative values are clamped to 0.
    ///
    /// Errors from the system badge API are logged and swallowed, so call sites do not
    /// need `try`.
    public static func setBadge(_ count: Int) async {
        await setSystemBadge(clampedBadgeCount(count))
    }

    /// Clear the application icon badge.
    public static func resetBadge() async {
        await setBadge(0)
    }

    static var isForegroundBadgeResetObserverRegistered: Bool {
        foregroundObserverToken != nil
    }

    static func clampedBadgeCount(_ count: Int) -> Int {
        max(0, count)
    }

    /// Applies config-driven badge behavior. Called from initialize(); tears down any
    /// prior observer first so re-initializing with the flag off takes effect.
    static func configureBadgeFeatures(config: HightouchPushConfig) {
        if let token = foregroundObserverToken {
            NotificationCenter.default.removeObserver(token)
            foregroundObserverToken = nil
        }
        guard config.autoClearBadgeOnForeground else { return }
        foregroundObserverToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await HightouchPush.resetBadge() }
        }
    }

    private static func setSystemBadge(_ count: Int) async {
        if #available(iOS 16.0, *) {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(count)
            } catch {
                analytics.log(message: "[HightouchPush] setBadgeCount failed: \(error)")
            }
        } else {
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
    }
}

#else

extension HightouchPush {
    static func configureBadgeFeatures(config: HightouchPushConfig) {}
}

#endif
