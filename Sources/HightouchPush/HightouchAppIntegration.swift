#if os(iOS) || targetEnvironment(macCatalyst)

import Foundation
import UIKit
import UserNotifications

/// Forwards push notification lifecycle events from your AppDelegate to the Hightouch SDK.
///
/// iOS delivers notification tap events to a single delegate registered by the app. Rather than
/// registering its own delegate (which would displace whatever delegate the app already has),
/// the SDK exposes explicit forwarding methods that the developer calls from their own delegate.
///
/// Minimum wiring required in AppDelegate:
///
///     func userNotificationCenter(
///         _ center: UNUserNotificationCenter,
///         didReceive response: UNNotificationResponse,
///         withCompletionHandler completionHandler: @escaping () -> Void
///     ) {
///         HightouchAppIntegration.userNotificationCenter(
///             center, didReceive: response, withCompletionHandler: completionHandler
///         )
///     }
public enum HightouchAppIntegration {

    /// Call from userNotificationCenter(_:didReceive:withCompletionHandler:).
    ///
    /// Reads the hightouch payload wrapper, resolves the action (defaultAction or the tapped
    /// action button), routes it to urlDelegate / customActionDelegate or falls back to
    /// UIApplication.shared.open, and fires a track("CEP Engagement Events") event with
    /// provider_event_type "opened".
    public static func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier

        if actionId == UNNotificationDismissActionIdentifier {
            completionHandler()
            return
        }

        guard let payload = HTPushPayload(userInfo) else {
            completionHandler()
            return
        }

        let action: HightouchAction?
        let source: HightouchActionSource

        switch actionId {
        case UNNotificationDefaultActionIdentifier:
            action = payload.defaultAction
            source = .push
        default:
            action = findActionButton(actionId, in: payload)
            source = .actionButton(identifier: actionId)
        }

        let normalizedActionId = actionId == UNNotificationDefaultActionIdentifier
            ? "default"
            : actionId

        CepEventTracking.track(
            name: CepEventTracking.engagementEvents,
            properties: [
                "provider_event_type": CepEventTracking.pushOpened,
                "action": ["identifier": normalizedActionId],
            ],
            messageContext: payload.messageContext ?? [:]
        )

        if let action = action {
            routeAction(action, source: source)
        }

        completionHandler()
    }

    /// Call from application(_:didReceiveRemoteNotification:fetchCompletionHandler:) to handle
    /// silent push notifications.
    public static func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // TODO: Process silent push notifications
        completionHandler(.noData)
    }

    private static func findActionButton(
        _ actionId: String, in payload: HTPushPayload?
    ) -> HightouchAction? {
        return payload?.actionButtons?.first { $0.identifier == actionId }?.action
    }

    private static func routeAction(_ action: HightouchAction, source: HightouchActionSource) {
        let context = HightouchActionContext(source: source)

        if action.type == "openUrl" {
            guard let urlString = action.data, let url = URL(string: urlString) else {
                return
            }
            let handled = HightouchPush.urlDelegate?.handle(url: url, inContext: context) ?? false
            if handled { return }

            let scheme = url.scheme?.lowercased() ?? ""
            let isAllowed = scheme == "https" || HightouchPush.allowedProtocols.contains(scheme)
            guard isAllowed else {
                print("[HightouchPush] Dropping URL with disallowed scheme '\(scheme)'. Add it to HightouchPushConfig.allowedProtocols to opt in.")
                return
            }

            // For https URLs, iOS routes through Universal Link (AASA) handling automatically
            // when the URL matches the app's Associated Domains; otherwise it opens in Safari.
            // For opted-in custom schemes, iOS dispatches to whichever app claims the scheme.
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:]) { success in
                    if !success {
                        print("[HightouchPush] UIApplication.shared.open failed for URL: \(url)")
                    }
                }
            }
        } else {
            _ = HightouchPush.customActionDelegate?.handle(
                customAction: action, inContext: context
            )
        }
    }
}

#endif
