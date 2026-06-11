import Foundation

/// Implement to handle deep link URLs from push notification taps.
///
/// Return true if your app handled the URL. Return false to fall back to
/// UIApplication.shared.open(url), which respects iOS Universal Links (AASA)
/// for matching Associated Domains and otherwise opens the URL in the system
/// browser. Non-https schemes are only opened if listed in
/// HightouchPushConfig.allowedProtocols.
public protocol HightouchURLDelegate: AnyObject {
    func handle(url: URL, inContext context: HightouchActionContext) -> Bool
}

/// Implement to handle custom action types (non-URL actions) from push notification buttons.
///
/// Return true if your app handled the action.
public protocol HightouchCustomActionDelegate: AnyObject {
    func handle(customAction action: HightouchAction, inContext context: HightouchActionContext) -> Bool
}

public struct HightouchAction {
    /// The action type string from the payload (e.g. "openUrl", or a custom type).
    public let type: String
    /// The URL string for "openUrl" actions, or arbitrary data for custom types.
    public let data: String?
}

public struct HightouchActionContext {
    public let source: HightouchActionSource
}

public enum HightouchActionSource {
    /// The user tapped the notification body.
    case push
    /// The user tapped a named action button.
    case actionButton(identifier: String)
}

