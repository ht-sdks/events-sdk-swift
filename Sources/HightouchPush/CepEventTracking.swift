import Foundation

/// Shared CEP event constants and track helper.
enum CepEventTracking {

    static let pushTokenEvents = "CEP Push Token Events"
    static let engagementEvents = "CEP Engagement Events"

    /// Provider event type values (lowercase, single verb). The
    /// category-vs-subtype split happens at the track-event-name layer
    /// (CepEventTracking.pushTokenEvents), so the value here doesn't
    /// need to repeat "Push Token".
    static let tokenRegistered = "registered"
    static let tokenDisabled = "disabled"
    /// Canonical event type value sent on the wire.
    static let pushOpened = "opened"

    /// Properties attached to every CEP push event.
    static func baseProperties() -> [String: Any] {
        [
            "channel_type": "push",
            "_ht_cep_source": "push_sdk",
            "app_id": HightouchPush.appId,
        ]
    }

    /// Track a CEP event with base properties merged in.
    static func track(
        name: String,
        properties: [String: Any] = [:],
        messageContext: [String: Any] = [:]
    ) {
        let merged = mergedProperties(properties: properties, messageContext: messageContext)
        HightouchPush.analytics.track(name: name, properties: merged)
    }

    /// Precedence (highest wins): `baseProperties` > `properties` > `messageContext`.
    /// `messageContext` is the opaque bag delivered inside the push payload; it fills in
    /// keys that neither the system nor the caller set, and can never stomp on them.
    static func mergedProperties(
        properties: [String: Any],
        messageContext: [String: Any]
    ) -> [String: Any] {
        var merged = messageContext
        for (key, value) in properties { merged[key] = value }
        for (key, value) in baseProperties() { merged[key] = value }
        return merged
    }
}
