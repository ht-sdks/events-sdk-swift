import Foundation
import Hightouch

/// The single identity messages are scoped to: `userId` when set, else `anonymousId`.
struct MessageOwner: Equatable {
    enum Kind: String {
        case userId
        case anonymousId
    }

    let kind: Kind
    let id: String

    var storageKey: String {
        "\(kind == .userId ? "u" : "a"):\(id)"
    }

    static func current(analytics: Analytics) -> MessageOwner? {
        if let userId = analytics.userId, !userId.isEmpty {
            return MessageOwner(kind: .userId, id: userId)
        }

        let anonymousId = analytics.anonymousId
        if !anonymousId.isEmpty {
            return MessageOwner(kind: .anonymousId, id: anonymousId)
        }

        return nil
    }
}
