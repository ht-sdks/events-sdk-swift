import Foundation
import Hightouch

/// Reported once per sync when some entries in an otherwise-successful fetch failed to decode.
struct MalformedMessagesError: Error {
    let count: Int
}

/// A 2xx body with no `messages` array. Failing the sync matters: parsing it as empty would make
/// `replaceAll` delete every cached message for the owner.
struct MissingMessagesArrayError: Error {}

/// The decoded result of a messages fetch, treated as the owner's complete set: `replaceAll`
/// deletes anything it omits. The gateway returns every unexpired message in one response, and
/// this endpoint must never paginate, since released SDKs would take a page for the full set.
struct MessagesFetchResponse {
    let messages: [HightouchMessage]
    let malformedCount: Int

    /// Accepts `{"messages": [...]}` or a bare array; anything else throws. A malformed entry is
    /// counted and dropped rather than failing the parse.
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
