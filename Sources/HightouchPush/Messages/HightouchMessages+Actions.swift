import Foundation
import Hightouch

public extension HightouchMessages {

    /// Records a message impression. Call when the message is actually visible, not when it's fetched.
    static func trackImpression(messageId: String) {
        trackLifecycleEvent(providerEventType: CepEventTracking.messageDisplayed, messageId: messageId)
    }

    /// Records a click. The host performs whatever the tap does; `identifier` names what was
    /// tapped and defaults to `"default"`, as a push body tap does.
    static func trackClick(messageId: String, identifier: String? = nil) {
        trackLifecycleEvent(
            providerEventType: CepEventTracking.messageClicked,
            messageId: messageId,
            extraProperties: ["action": ["identifier": identifier ?? "default"]]
        )
    }

    /// Records that the user dismissed a message, then removes it from local storage. A later sync
    /// won't bring it back.
    static func trackDismissed(messageId: String) {
        trackLifecycleEvent(providerEventType: CepEventTracking.messageDismissed, messageId: messageId)
        #if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
        removeDismissed(messageId: messageId)
        #endif
    }
}

extension HightouchMessages {
    /// Test seam.
    static func messageContextForTesting(messageId: String) -> [String: Any] {
        messageContext(forMessageId: messageId)
    }
}

// MARK: - Test seam

extension HightouchMessages {
    /// Test seam: overrides `canTrack`. Needed because `HightouchPush` has no reset, so once any test
    /// initializes it, `isInitialized` stays true for the rest of the process.
    static var isPushInitializedOverrideForTesting: Bool?
}

// MARK: - Analytics

private extension HightouchMessages {

    /// `HightouchPush.analytics` traps in DEBUG before `HightouchPush.initialize()`, and a message can
    /// be tapped before it runs.
    static var canTrack: Bool {
        isPushInitializedOverrideForTesting ?? HightouchPush.isInitialized
    }

    static func messageContext(forMessageId messageId: String) -> [String: Any] {
        message(withId: messageId)?.raw["messageContext"]?.dictionaryValue ?? [:]
    }

    static func trackLifecycleEvent(
        providerEventType: String,
        messageId: String,
        extraProperties: [String: Any] = [:]
    ) {
        guard canTrack else { return }

        var properties = extraProperties
        properties["provider_event_type"] = providerEventType
        properties["message_id"] = messageId

        CepEventTracking.track(
            name: CepEventTracking.engagementEvents,
            properties: properties,
            messageContext: messageContext(forMessageId: messageId),
            channel: .inApp
        )
    }
}
