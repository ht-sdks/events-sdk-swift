import Foundation

public struct HightouchPushConfig {

    /// The push app ID (UUID) assigned by Hightouch when the app is registered.
    /// Included in every push token event.
    public let appId: String

    /// Handles deep link URLs from push notification taps.
    ///
    /// The SDK calls handle(url:inContext:) when the user taps the notification body or an action
    /// button whose action type is "openUrl". If this delegate is nil or returns false, the SDK
    /// falls back to UIApplication.shared.open(url), which respects iOS Universal Links (AASA)
    /// for matching Associated Domains and otherwise opens the URL in the system browser.
    /// Non-https schemes are only opened if listed in `allowedProtocols`.
    public weak var urlDelegate: (any HightouchURLDelegate)?

    /// Handles custom action types from push notification action buttons.
    ///
    /// Called when the user taps a button whose action type is not "openUrl".
    public weak var customActionDelegate: (any HightouchCustomActionDelegate)?

    /// Additional URL schemes the SDK is allowed to open when falling back to
    /// UIApplication.shared.open. The "https" scheme is always allowed. Add other schemes
    /// (e.g. "myapp", "tel", "sms") to opt them in. URLs whose scheme is not "https" and
    /// not in this list are dropped after the urlDelegate declines them.
    public var allowedProtocols: [String] = []

    public init(appId: String) {
        self.appId = appId
    }
}
