import Foundation

/// Parses a ghost-push command from the raw APNs payload. Read directly rather than through
/// `HTPushPayload`, which requires `hightouch.messageId` — a command-only push may omit it.
struct HTMessageCommand {

    /// Unrecognized verbs fail `init?`, so older SDKs ignore verbs added later.
    enum Verb: String {
        case syncMessages
        case deleteMessage
    }

    let verb: Verb

    /// Operand for `deleteMessage`; unused by `syncMessages`.
    let messageId: String?

    /// `hightouch.messageId`, used only to attribute the `delivered` event.
    let pushMessageId: String?

    // Advisory only: logged on the `delivered` event, never used to decide what is stored or to
    // skip a fetch. Background pushes can be dropped, so only a full refresh converges.
    let reason: String?
    let messageIds: [String]?
    let locationIds: [String]?
    let syncToken: String?

    let messageContext: [String: Any]?

    init?(_ userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo[PayloadKey.hightouch] as? [String: Any],
              let commandDict = raw[PayloadKey.command] as? [String: Any],
              let verbString = commandDict[PayloadKey.verb] as? String,
              let verb = Verb(rawValue: verbString) else {
            return nil
        }

        self.verb = verb
        self.messageId = commandDict[PayloadKey.messageId] as? String
        self.pushMessageId = raw[PayloadKey.messageId] as? String
        self.reason = commandDict[PayloadKey.reason] as? String
        self.messageIds = commandDict[PayloadKey.messageIds] as? [String]
        self.locationIds = commandDict[PayloadKey.locationIds] as? [String]
        self.syncToken = commandDict[PayloadKey.syncToken] as? String
        self.messageContext = raw[PayloadKey.messageContext] as? [String: Any]
    }
}
