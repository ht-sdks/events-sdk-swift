import Foundation
import Hightouch

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#endif

public final class HightouchPush {
    private init() {}

    private static let apnsTokenKey = "com.hightouch.push.apnsToken"
    private static let lastTokenUploadAtKey = "com.hightouch.push.lastTokenUploadAt"

    // NOTE: Thread safety — these static vars are not synchronized. In practice, identify(),
    // logout(), and register() are called from single callsites (login button, logout button,
    // OS callback), so concurrent access is unlikely. If this becomes an issue, wrap state
    // mutations in a serial DispatchQueue. @Atomic alone is insufficient because identify()
    // does a compound read-check-write on _currentUserId.
    private static var _analytics: Analytics?
    private static var _config: HightouchPushConfig?
    static var urlDelegate: (any HightouchURLDelegate)? { _config?.urlDelegate }
    static var customActionDelegate: (any HightouchCustomActionDelegate)? { _config?.customActionDelegate }
    static var silentPushDelegate: (any HightouchSilentPushDelegate)? { _config?.silentPushDelegate }
    static var allowedProtocols: [String] { _config?.allowedProtocols ?? [] }
    static var appId: String { _config?.appId ?? "" }
    static var tokenUploadInterval: TimeInterval {
        _config?.tokenUploadInterval ?? HightouchPushConfig.defaultTokenUploadInterval
    }
    private static var _apnsToken: Data?
    private static var _currentUserId: String?
    #if os(iOS) || targetEnvironment(macCatalyst)
    private static var foregroundHeartbeatObserverToken: NSObjectProtocol?
    #endif

    /// Set by `identify(...)` so the next `register` re-uploads even within the heartbeat interval
    /// (a login must re-associate the token). Cleared by that `register(token:)`.
    private static var _forceUploadNextRegister = false

    static var analytics: Analytics {
        if let a = _analytics {
            return a
        }
        assertionFailure("[HightouchPush] Call initialize() before using the SDK.")
        return Analytics(configuration: Configuration(writeKey: "uninitialized"))
    }

    /// Canonical form of a URL scheme: lowercased (schemes are case-insensitive per RFC 3986)
    /// and stripped of surrounding whitespace.
    static func normalizeScheme(_ scheme: String) -> String {
        scheme.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Whether the SDK may open a URL with the given scheme. "https" is always allowed; any other
    /// scheme must appear in `allowedProtocols`. Self-contained (normalizes both sides) so the
    /// allow decision is unit-testable without the iOS notification flow.
    static func isSchemeAllowed(_ scheme: String, allowedProtocols: [String]) -> Bool {
        let normalized = normalizeScheme(scheme)
        if normalized == "https" { return true }
        return allowedProtocols.contains { normalizeScheme($0) == normalized }
    }

    /// Returns a copy of the push config with `allowedProtocols` canonicalized to lowercased,
    /// trimmed scheme names, and `tokenUploadInterval` clamped to its minimum. Applied when the
    /// config enters the SDK so every reader sees clean data.
    private static func normalizeConfig(_ config: HightouchPushConfig) -> HightouchPushConfig {
        var normalized = config
        normalized.allowedProtocols = config.allowedProtocols.map(normalizeScheme)
        normalized.tokenUploadInterval = clampTokenUploadInterval(config.tokenUploadInterval)
        return normalized
    }

    /// Clamps a configured interval up to `HightouchPushConfig.minTokenUploadInterval`.
    static func clampTokenUploadInterval(_ interval: TimeInterval) -> TimeInterval {
        return max(interval, HightouchPushConfig.minTokenUploadInterval)
    }

    /// Initialize with an analytics `Configuration`. HightouchPush builds and owns the
    /// underlying `Analytics` instance from it.
    ///
    /// Use this if you are not already using Hightouch Analytics. Because you supply the full
    /// `Configuration`, every analytics option is set exactly as in the base SDK — including
    /// the region endpoints required for non-default workspaces:
    ///
    ///     let configuration = Configuration(writeKey: "WRITE_KEY")
    ///         .apiHost("ap-south-1.hightouch-events.com/v1")
    ///         .cdnHost("ap-south-1.hightouch-events.com/v1")
    ///     HightouchPush.initialize(
    ///         configuration: configuration,
    ///         config: HightouchPushConfig(appId: "APP_ID")
    ///     )
    public static func initialize(
        configuration: Configuration,
        config: HightouchPushConfig
    ) {
        let a = Analytics(configuration: configuration)
        _analytics = a
        _config = normalizeConfig(config)
        _currentUserId = a.userId
        _apnsToken = UserDefaults.standard.data(forKey: apnsTokenKey)
        configureBadgeFeatures(config: config)
        configureForegroundHeartbeat()
    }

    /// Initialize with an existing Analytics instance.
    ///
    /// Use this if you already use Hightouch Analytics and want push on top.
    /// All events go through the provided instance — no second pipeline is created.
    ///
    /// Analytics+Push customers should use HightouchPush.identify() instead of
    /// analytics.identify() directly — see identify() for why.
    public static func initialize(
        analytics: Analytics,
        config: HightouchPushConfig
    ) {
        _analytics = analytics
        _config = normalizeConfig(config)
        _currentUserId = analytics.userId
        _apnsToken = UserDefaults.standard.data(forKey: apnsTokenKey)
        configureBadgeFeatures(config: config)
        configureForegroundHeartbeat()
    }
}

extension HightouchPush {

    /// Call from application(_:didRegisterForRemoteNotificationsWithDeviceToken:).
    ///
    /// The developer wires this up once. The SDK calls
    /// UIApplication.shared.registerForRemoteNotifications() internally on identify(), so this
    /// callback fires automatically on every login — no manual call needed on login.
    ///
    /// What this does:
    /// 1. Stores the token and calls analytics.setDeviceToken(_:) on every call, so events stay
    ///    tagged via context.device.token.
    /// 2. Fires track("CEP Push Token Events") "registered" — deduped, since iOS re-fires this per
    ///    launch: only when the token changed or the heartbeat interval elapsed (see
    ///    `shouldUploadToken`). `identify(...)` bypasses the dedup so a login always re-associates.
    public static func register(token: Data) {
        let previousToken = _apnsToken
        let hexToken = token.map { String(format: "%02x", $0) }.joined()

        _apnsToken = token
        UserDefaults.standard.set(token, forKey: apnsTokenKey)

        #if os(iOS) || targetEnvironment(macCatalyst)
        analytics.registeredForRemoteNotifications(deviceToken: token)
        #else
        analytics.setDeviceToken(hexToken)
        #endif

        let forceUpload = _forceUploadNextRegister
        _forceUploadNextRegister = false

        let now = Date().timeIntervalSince1970
        let lastUploadedAt = UserDefaults.standard.double(forKey: lastTokenUploadAtKey)
        let shouldUpload = forceUpload || shouldUploadToken(
            tokenChanged: previousToken != token,
            lastUploadedAt: lastUploadedAt,
            now: now,
            interval: tokenUploadInterval
        )
        guard shouldUpload else { return }

        UserDefaults.standard.set(now, forKey: lastTokenUploadAtKey)
        CepEventTracking.track(name: CepEventTracking.pushTokenEvents, properties: [
            "provider_event_type": CepEventTracking.tokenRegistered,
            "token": hexToken,
            "platform": "ios",
        ])
    }

    /// Re-upload when the token changed since the last upload, or the heartbeat interval has
    /// elapsed. A `lastUploadedAt` of `0` (never uploaded) always uploads, since a real epoch `now`
    /// dwarfs the interval.
    static func shouldUploadToken(
        tokenChanged: Bool,
        lastUploadedAt: TimeInterval,
        now: TimeInterval,
        interval: TimeInterval
    ) -> Bool {
        return tokenChanged || (now - lastUploadedAt) >= interval
    }
}

extension HightouchPush {

    /// Identify the current user.
    ///
    /// This is NOT the same as calling analytics.identify() directly. Beyond identifying the
    /// user, it handles two push-specific responsibilities:
    ///
    /// 1. TOKEN RE-REGISTRATION — calls UIApplication.shared.registerForRemoteNotifications()
    ///    internally. This causes iOS to re-fire didRegisterForRemoteNotificationsWithDeviceToken,
    ///    which the developer has already wired to HightouchPush.register(token:). The result is
    ///    a fresh track("CEP Push Token Events") event with provider_event_type "registered"
    ///    carrying the new userId — without the
    ///    developer needing to do anything extra on login.
    ///
    /// 2. USER-SWITCH — if a DIFFERENT user was previously identified, calls logout() first
    ///    to cleanly disassociate the old user's token before identifying the new one.
    ///    This means analytics.reset() IS called on user-switch, generating a new anonymousId.
    ///    The anonymousId instability across user-switches is a known open question.
    ///
    ///   No previous user  →  registerForRemoteNotifications()
    ///                        analytics.identify(newUserId)
    ///
    ///   Same user again   →  registerForRemoteNotifications()
    ///                        analytics.identify(userId)
    ///
    ///   Different user    →  logout()                            (disassociate + reset)
    ///                        registerForRemoteNotifications()
    ///                        analytics.identify(newUserId)
    ///
    /// Analytics+Push customers must use HightouchPush.identify() instead of
    /// analytics.identify() directly, so that neither of the above steps is skipped.
    public static func identify(userId: String) {
        performIdentify(userId: userId) {
            analytics.identify(userId: userId)
        }
    }

    /// Identify the current user and record traits. Mirrors `Analytics.identify(userId:traits:)`.
    public static func identify(userId: String, traits: [String: Any]? = nil) {
        performIdentify(userId: userId) {
            analytics.identify(userId: userId, traits: traits)
        }
    }

    /// Identify the current user and record typed (Codable) traits.
    /// Mirrors `Analytics.identify(userId:traits:)`.
    public static func identify<T: Codable>(userId: String, traits: T?) {
        performIdentify(userId: userId) {
            analytics.identify(userId: userId, traits: traits)
        }
    }

    /// Shared push-specific identify behavior — user-switch logout and APNs token
    /// re-registration — followed by the supplied analytics identify call.
    private static func performIdentify(userId: String, emit: () -> Void) {
        if let current = _currentUserId, current != userId {
            logout()
        }

        _currentUserId = userId

        #if os(iOS) || targetEnvironment(macCatalyst)
        // The OS re-fires didRegister (→ register) with the same token; force that upload past the
        // heartbeat dedup so the token is re-associated with the new user.
        _forceUploadNextRegister = true
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        #endif

        emit()
    }

    /// The userId of the currently identified user. Nil if no user is identified.
    public static var userId: String? {
        return _currentUserId
    }

    /// The stable anonymous ID for this device. Generated on first launch, persists across sessions.
    ///
    /// NOTE: analytics.reset() (called by logout()) generates a new anonymousId, breaking stable
    /// device identity across logouts. This is a known open question — see the design doc.
    public static var anonymousId: String {
        return analytics.anonymousId
    }
}

extension HightouchPush {

    /// Log out the current user.
    ///
    /// 1. Fires track("CEP Push Token Events") with provider_event_type "disabled" so the
    ///    token is disassociated from the current user.
    /// 2. Calls analytics.reset(), which clears userId and generates a new anonymousId.
    ///
    /// Called both explicitly by the developer and internally by identify() on user-switch.
    public static func logout() {
        guard _currentUserId != nil else { return }

        if let token = _apnsToken {
            let hexToken = token.map { String(format: "%02x", $0) }.joined()
            CepEventTracking.track(name: CepEventTracking.pushTokenEvents, properties: [
                "provider_event_type": CepEventTracking.tokenDisabled,
                "token": hexToken,
                "userId": _currentUserId as Any,
            ])
        }

        _currentUserId = nil
        analytics.reset()
    }
}

extension HightouchPush {

    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Whether the app-foreground token-upload heartbeat observer is registered.
    static var isForegroundHeartbeatObserverRegistered: Bool {
        foregroundHeartbeatObserverToken != nil
    }

    /// Observe app-foreground so the heartbeat also fires when a long-lived process returns to the
    /// foreground past the TTL, not only on launch. Still gated by `register`'s dedup, so
    /// foregrounds within the interval are no-ops. Registered once from initialize(); idempotent.
    static func configureForegroundHeartbeat() {
        guard foregroundHeartbeatObserverToken == nil else { return }
        foregroundHeartbeatObserverToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            HightouchPush.handleForegroundHeartbeat()
        }
    }

    /// Re-affirm the cached APNs token through the dedup gate on foreground. A no-op until a token
    /// has been delivered — the OS `didRegister` callback handles the first upload.
    static func handleForegroundHeartbeat() {
        guard let token = _apnsToken else { return }
        register(token: token)
    }
    #else
    static func configureForegroundHeartbeat() {}
    #endif
}
