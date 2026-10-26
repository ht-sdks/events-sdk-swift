import Foundation

/// Notifies the host when the local message cache changes. Held weakly by
/// `HightouchMessagesConfig`; `.hightouchMessagesDidChange` needs no retained delegate.
public protocol HightouchMessagesDelegate: AnyObject {
    func hightouchMessagesDidChange(_ change: HightouchMessagesChange)
}

public extension HightouchMessagesDelegate {
    func hightouchMessagesDidChange(_ change: HightouchMessagesChange) {}
}

/// Describes what changed in the local message cache after a successful sync.
public struct HightouchMessagesChange {
    public let insertedIds: [String]
    public let updatedIds: [String]
    public let removedIds: [String]

    public init(insertedIds: [String] = [], updatedIds: [String] = [], removedIds: [String] = []) {
        self.insertedIds = insertedIds
        self.updatedIds = updatedIds
        self.removedIds = removedIds
    }
}

public extension Notification.Name {
    /// Posted on the main queue when the local message cache changes.
    static let hightouchMessagesDidChange = Notification.Name("com.hightouch.messages.didChange")
}
