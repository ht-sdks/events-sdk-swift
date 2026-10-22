import Foundation

/// Shared CEP event constants and track helper.
enum CepEventTracking {

    static let pushTokenEvents = "CEP Push Token Events"
    static let engagementEvents = "CEP Engagement Events"

    /// The channel an event belongs to. Sent as `channel_type`; also selects `_ht_cep_source`.
    enum Channel: String {
        case push
        case inApp = "in_app"

        var source: String {
            switch self {
            case .push:  return "push_sdk"
            case .inApp: return "in_app_sdk"
            }
        }
    }

    /// Provider event type values (lowercase, single verb). The
    /// category-vs-subtype split happens at the track-event-name layer
    /// (CepEventTracking.pushTokenEvents), so the value here doesn't
    /// need to repeat "Push Token".
    static let tokenRegistered = "registered"
    static let tokenDisabled = "disabled"
    /// Canonical event type value sent on the wire.
    static let pushOpened = "opened"
    static let pushDelivered = "delivered"

    // In-app events share `engagementEvents` with push; `channel_type` distinguishes them.
    static let messageDisplayed = "displayed"
    /// Deliberately not `opened`, which for push means the notification opened the app.
    static let messageClicked = "clicked"
    static let messageDismissed = "dismissed"

    /// Properties attached to every CEP event.
    static func baseProperties(channel: Channel = .push) -> [String: Any] {
        [
            "channel_type": channel.rawValue,
            "_ht_cep_source": channel.source,
            "app_id": HightouchPush.appId,
        ]
    }

    /// Track a CEP event with base properties merged in.
    static func track(
        name: String,
        properties: [String: Any] = [:],
        messageContext: [String: Any] = [:],
        channel: Channel = .push
    ) {
        let merged = mergedProperties(properties: properties, messageContext: messageContext, channel: channel)
        HightouchPush.analytics.track(name: name, properties: merged)
    }

    /// Precedence (highest wins): `baseProperties` > `properties` > `messageContext`.
    /// `messageContext` is the opaque bag delivered inside the push payload; it fills in
    /// keys that neither the system nor the caller set, and can never stomp on them.
    static func mergedProperties(
        properties: [String: Any],
        messageContext: [String: Any],
        channel: Channel = .push
    ) -> [String: Any] {
        var merged = messageContext
        for (key, value) in properties { merged[key] = value }
        for (key, value) in baseProperties(channel: channel) { merged[key] = value }
        return merged
    }
}
