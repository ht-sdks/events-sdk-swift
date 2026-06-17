import Foundation

/// Keys for the `hightouch` wrapper inside the APNs userInfo payload.
enum PayloadKey {
    static let hightouch = "hightouch"
    static let messageId = "messageId"
    static let attachmentUrl = "attachmentUrl"
    static let defaultAction = "defaultAction"
    static let actionButtons = "actionButtons"
    static let messageContext = "messageContext"
    static let customData = "customData"
    static let identifier = "identifier"
    static let title = "title"
    static let action = "action"
    static let type = "type"
    static let data = "data"
    static let buttonType = "buttonType"
    static let openApp = "openApp"
    static let requiresUnlock = "requiresUnlock"
    static let inputTitle = "inputTitle"
    static let inputPlaceholder = "inputPlaceholder"
    static let actionIcon = "actionIcon"
    static let iconType = "iconType"
    static let iconName = "iconName"
}

struct HTActionButton {
    let identifier: String
    let action: HightouchAction?
    /// The original dictionary, retained for the NSE which needs rendering fields (title, buttonType, icons).
    let rawDict: [String: Any]

    init?(_ dict: [String: Any]) {
        guard let identifier = dict[PayloadKey.identifier] as? String else { return nil }
        self.identifier = identifier
        self.action = HTPushPayload.parseAction(dict[PayloadKey.action] as? [String: Any])
        self.rawDict = dict
    }
}

struct HTPushPayload {
    let messageId: String
    let attachmentUrl: String?
    let defaultAction: HightouchAction?
    let actionButtons: [HTActionButton]?

    /// Opaque round-trip context from `hightouch.messageContext` in the APNS payload.
    /// The SDK merges these keys into the engagement event's top-level `properties`
    /// without interpreting any of them.
    let messageContext: [String: Any]?

    let customData: [String: String]?

    init?(_ userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo[PayloadKey.hightouch] as? [String: Any],
              let messageId = raw[PayloadKey.messageId] as? String else { return nil }
        self.messageId = messageId
        self.attachmentUrl = raw[PayloadKey.attachmentUrl] as? String
        defaultAction = Self.parseAction(raw[PayloadKey.defaultAction] as? [String: Any])
        actionButtons = (raw[PayloadKey.actionButtons] as? [[String: Any]])?.compactMap(HTActionButton.init)
        messageContext = raw[PayloadKey.messageContext] as? [String: Any]
        customData = raw[PayloadKey.customData] as? [String: String]
    }

    static func parseAction(_ dict: [String: Any]?) -> HightouchAction? {
        guard let dict = dict, let type = dict[PayloadKey.type] as? String else { return nil }
        return HightouchAction(type: type, data: dict[PayloadKey.data] as? String)
    }
}
