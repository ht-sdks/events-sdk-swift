import Foundation
import Hightouch

/// Reported once per sync when some entries in an otherwise-successful fetch failed to decode.
struct MalformedMessagesError: Error {
    let count: Int
}

/// A 2xx body with no `messages` array. Failing the sync matters: parsing it as empty would make
/// `replaceAll` delete every cached message for the owner.
struct MissingMessagesArrayError: Error {}

/// The decoded result of a messages fetch. Treated as the authoritative full set for the owner:
/// `replaceAll` deletes anything it omits, so a paged response would lose data.
struct MessagesFetchResponse {
    let messages: [HightouchMessage]
    let malformedCount: Int

    /// Accepts `{"messages": [...]}` or a bare array; anything else throws. A malformed entry is
    /// counted and dropped; it never fails the whole sync.
    static func parse(_ data: Data) throws -> MessagesFetchResponse {
        let envelope = try JSONDecoder().decode(JSON.self, from: data)

        let rawMessages: [JSON]
        switch envelope {
        case .array(let array):
            rawMessages = array
        case .object(let object):
            guard case .array(let array)? = object["messages"] else {
                throw MissingMessagesArrayError()
            }
            rawMessages = array
        default:
            throw MissingMessagesArrayError()
        }

        var messages: [HightouchMessage] = []
        messages.reserveCapacity(rawMessages.count)
        var malformedCount = 0
        for raw in rawMessages {
            if let message = try? HightouchMessage(raw: raw) {
                messages.append(message)
            } else {
                malformedCount += 1
            }
        }

        return MessagesFetchResponse(messages: messages, malformedCount: malformedCount)
    }
}
