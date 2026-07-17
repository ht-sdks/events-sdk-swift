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

    /// Consumes custom data delivered by silent (background) pushes.
    ///
    /// Silent pushes display nothing; their only payload is custom data (and optionally a
    /// badge, which iOS applies on its own). If this delegate is nil, silent pushes complete
    /// immediately with no effect. The config holds only a weak reference — keep a strong
    /// reference to the delegate for the app's lifetime (e.g. a static property), and set it
    /// before initialize() so it exists when iOS launches the app into the background.
    public weak var silentPushDelegate: (any HightouchSilentPushDelegate)?

    /// When true, the SDK observes UIApplication.didBecomeActiveNotification and clears the
    /// application icon badge each time the app enters the foreground. Off by default —
    /// hosts that manage their own badge state should leave this off.
    public var autoClearBadgeOnForeground: Bool = false

    /// Additional URL schemes the SDK is allowed to open when falling back to
    /// UIApplication.shared.open. The "https" scheme is always allowed. Add other schemes as
    /// bare scheme names (e.g. "myapp", "tel", "sms" — not "myapp://"). Matching is
    /// case-insensitive and ignores surrounding whitespace. URLs whose scheme is not "https"
    /// and not in this list are dropped after the urlDelegate declines them.
    public var allowedProtocols: [String] = []

    /// How long a token registration stays "fresh" before `register(token:)` re-uploads it,
    /// even when the APNs token is unchanged. This heartbeat keeps the server's `last_seen_at` a
    /// real liveness signal and lets a token that was wrongly invalidated (e.g. by the uninstall
    /// probe) self-revive on the next launch past this interval.
    ///
    /// Defaults to `defaultTokenUploadInterval` (24h) and is clamped up to
    /// `minTokenUploadInterval` (12h) when the SDK ingests the config — a shorter interval would
    /// risk re-uploading on every launch. There is intentionally no way to disable it:
    /// dedupe-forever is the failure mode this heartbeat removes.
    public var tokenUploadInterval: TimeInterval = HightouchPushConfig.defaultTokenUploadInterval

    /// Default token re-upload heartbeat interval: 24h, matching Airship.
    public static let defaultTokenUploadInterval: TimeInterval = 24 * 60 * 60

    /// Lower bound the heartbeat interval is clamped to, to avoid per-launch re-uploads.
    public static let minTokenUploadInterval: TimeInterval = 12 * 60 * 60

    public init(appId: String) {
        self.appId = appId
    }
}
