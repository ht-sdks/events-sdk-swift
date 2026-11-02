import Foundation

/// Configuration for embedded messages. Set it on `HightouchPushConfig.messages` to enable them.
public struct HightouchMessagesConfig {

    /// Held weakly: keep a strong reference elsewhere, or observe `.hightouchMessagesDidChange`.
    public weak var delegate: (any HightouchMessagesDelegate)?

    /// Bare host with no scheme. Defaults to `api.hightouch.com`. `https` is used except for a
    /// `localhost` host.
    public var messagesHost: String?

    /// Leading slash, no trailing slash.
    public var messagesPath: String = "/v1/inapp/messages"

    /// Reconcile with the server whenever the app becomes active, subject to the cooldown.
    public var syncOnForeground: Bool = false

    /// Reconcile with the server on every `HightouchPush.initialize`, bypassing the cooldown. Turning
    /// this off means an app that was force-quit when a ghost push arrived waits for the next sync
    /// trigger to catch up.
    public var syncOnLaunch: Bool = true

    /// Minimum time between foreground syncs for the same user. Clamped to at least 60 seconds.
    public var foregroundSyncCooldown: TimeInterval = 15 * 60

    /// Maximum messages kept locally across all users. A sync keeps the current user's
    /// highest-priority, newest messages up to this cap, then evicts other users' oldest-inserted
    /// messages to stay under it.
    public var maxStoredMessages: Int = 500

    /// Applied last to every fetch request, e.g. to route through a proxy.
    public var requestFactory: ((URLRequest) -> URLRequest)?

    public init() {}
}
