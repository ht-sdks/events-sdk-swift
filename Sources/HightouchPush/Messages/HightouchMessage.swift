import Foundation
import Hightouch

/// A message fetched from the in-app gateway and cached locally. `raw` keeps the complete
/// server payload, so fields not modeled here survive a round trip.
public struct HightouchMessage: Equatable {
    public let messageId: String
    public let messageType: String?
    public let campaignId: String?
    public let createdAt: Date?
    /// nil means the message never expires.
    public let expiresAt: Date?
    public let priority: HightouchMessagePriority
    public let locationId: String?
    public let variantSlug: String?
    public let triggerType: String?
    public let version: String?
    public let customValues: JSON?
    /**
     Opaque JSON from the server. The SDK stores it and returns it without validating it.

     `content["elements"]` is a flat array with one object per template field that has a value.
     `tag` identifies the field and `elementType` names its type, which decides the key that
     holds the value:

     - `Text`, `Number`, `Select`, `Toggle`, `Datetime`: a string under `text`.
     - `Asset`: a URL string under `mediaUrl`, with an optional `mediaCaption`.
     - `Json`: a parsed object or array under `json`, never a string. Read it with the `JSON`
       accessors, for example `element["json"]?["color"]?.stringValue`.

     The server omits a field that has no value, so look elements up by `tag`, treat every tag
     and key as optional, and skip an `elementType` the app does not know.
     */
    public let content: JSON?
    public let raw: JSON

    /// Unknown or wrongly-typed fields decode to nil; only a missing or empty `messageId` throws.
    public init(raw: JSON) throws {
        guard let messageId = raw["messageId"]?.stringValue, !messageId.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "HightouchMessage requires a non-empty \"messageId\"."
                )
            )
        }

        self.messageId = messageId
        self.messageType = raw["messageType"]?.stringValue
        self.campaignId = raw["campaignId"]?.stringValue
        self.createdAt = MessagesISO8601.date(from: raw["createdAt"])
        self.expiresAt = MessagesISO8601.date(from: raw["expiresAt"])
        self.priority = HightouchMessagePriority(payloadValue: raw["priority"])
        self.locationId = raw["locationId"]?.stringValue
        self.variantSlug = raw["variantSlug"]?.stringValue
        self.triggerType = raw["triggerType"]?.stringValue
        self.version = raw["version"]?.stringValue
        self.customValues = raw["customValues"]
        self.content = raw["content"]
        self.raw = raw
    }

    public init(
        messageId: String,
        messageType: String? = nil,
        campaignId: String? = nil,
        createdAt: Date? = nil,
        expiresAt: Date? = nil,
        priority: HightouchMessagePriority = .default,
        locationId: String? = nil,
        variantSlug: String? = nil,
        triggerType: String? = nil,
        version: String? = nil,
        customValues: JSON? = nil,
        content: JSON? = nil,
        raw: JSON = .object([:])
    ) {
        self.messageId = messageId
        self.messageType = messageType
        self.campaignId = campaignId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.priority = priority
        self.locationId = locationId
        self.variantSlug = variantSlug
        self.triggerType = triggerType
        self.version = version
        self.customValues = customValues
        self.content = content
        self.raw = raw
    }
}

extension HightouchMessage: Codable {
    public init(from decoder: Decoder) throws {
        try self.init(raw: JSON(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try raw.encode(to: encoder)
    }
}

extension HightouchMessage {
    var priorityRank: Int32 { priority.rank }

    /// Decodes a message from bytes previously produced by `payloadData()`.
    public static func decode(payload: Data) throws -> HightouchMessage {
        try JSONDecoder().decode(HightouchMessage.self, from: payload)
    }

    /// Encodes `raw` for persistence. Uses `.sortedKeys` so equal messages produce equal bytes.
    public func payloadData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(raw)
    }
}
