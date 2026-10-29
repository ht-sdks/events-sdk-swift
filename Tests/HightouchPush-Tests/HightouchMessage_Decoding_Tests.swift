import XCTest
@testable import HightouchPush
import Hightouch

final class HightouchMessage_Decoding_Tests: XCTestCase {

    // MARK: - Fixtures

    // A formatter with .withFractionalSeconds returns nil for a timestamp without them.
    private let fullPayloadString = """
    {"messageType":"embedded","messageId":"msg_1","campaignId":"camp_1","createdAt":"2026-08-01T12:00:00.000Z","expiresAt":"2026-09-01T12:00:00.000Z","priority":"high","locationId":"home_banner","triggerType":"immediate","customValues":{},"version":"1","variantSlug":"two-button","content":{"elements":[{"id":"1","tag":"background","elementType":"image","order":null,"mediaUrl":"https://hqcoffe.com/beans.jpg","mediaCaption":"HQ beans","text":null}]}}
    """

    private func makeJSON(_ jsonString: String) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: Data(jsonString.utf8))
    }

    private var fractionalFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.update(with: .withFractionalSeconds)
        return formatter
    }

    // MARK: - Full payload

    func testFullPayloadDecodesAllTypedFields() throws {
        let raw = try makeJSON(fullPayloadString)
        let message = try HightouchMessage(raw: raw)

        XCTAssertEqual(message.messageId, "msg_1")
        XCTAssertEqual(message.messageType, "embedded")
        XCTAssertEqual(message.campaignId, "camp_1")
        XCTAssertEqual(message.priority, .high)
        XCTAssertEqual(message.locationId, "home_banner")
        XCTAssertEqual(message.variantSlug, "two-button")
        XCTAssertEqual(message.triggerType, "immediate")
        XCTAssertEqual(message.version, "1")
        XCTAssertEqual(message.customValues, .object([:]))
        XCTAssertEqual(message.content?["elements"]?[0]?["id"]?.stringValue, "1")
        XCTAssertEqual(message.content?["elements"]?[0]?["tag"]?.stringValue, "background")
        XCTAssertEqual(message.content?["elements"]?[0]?["elementType"]?.stringValue, "image")
        XCTAssertEqual(message.content?["elements"]?[0]?["mediaUrl"]?.stringValue, "https://hqcoffe.com/beans.jpg")
        XCTAssertEqual(message.content?["elements"]?[0]?["mediaCaption"]?.stringValue, "HQ beans")
        XCTAssertEqual(message.raw, raw)

        XCTAssertEqual(message.createdAt, fractionalFormatter.date(from: "2026-08-01T12:00:00.000Z"))
        XCTAssertEqual(message.expiresAt, fractionalFormatter.date(from: "2026-09-01T12:00:00.000Z"))
    }

    // MARK: - Round trip

    func testRawRoundTripsThroughPayloadDataAndDecodeEqually() throws {
        let raw = try makeJSON(fullPayloadString)
        let message = try HightouchMessage(raw: raw)

        let data = try message.payloadData()
        let decoded = try HightouchMessage.decode(payload: data)

        XCTAssertEqual(decoded, message)
    }

    // MARK: - Unknown fields survive

    func testUnknownTopLevelKeysSurviveAndReencode() throws {
        let payloadString = """
        {"messageId":"msg_1","messageType":"embedded","aBrandNewServerField":{"nested":[1,2,3]}}
        """
        let raw = try makeJSON(payloadString)
        let message = try HightouchMessage(raw: raw)

        XCTAssertEqual(message.raw["aBrandNewServerField"]?["nested"]?[1]?.decimalValue, 2)

        let reencodedData = try JSONEncoder().encode(message)
        let reencoded = try JSONDecoder().decode(JSON.self, from: reencodedData)

        XCTAssertEqual(reencoded["aBrandNewServerField"], raw["aBrandNewServerField"])
    }

    func testMissingMessageIdThrows() throws {
        let raw = try makeJSON(#"{"messageType":"embedded"}"#)
        XCTAssertThrowsError(try HightouchMessage(raw: raw)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testEmptyMessageIdThrows() throws {
        let raw = try makeJSON(#"{"messageId":"","messageType":"embedded"}"#)
        XCTAssertThrowsError(try HightouchMessage(raw: raw)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testUnknownOrMistypedFieldsDoNotThrow() throws {
        let raw = try makeJSON(#"{"messageId":"msg_1","campaignId":42,"somethingNew":true}"#)
        let message = try HightouchMessage(raw: raw)

        XCTAssertNil(message.campaignId)
        XCTAssertEqual(message.raw["somethingNew"]?.boolValue, true)
    }

    // MARK: - Dates

    func testCreatedAtParsesBothFractionalAndPlainTimestamps() throws {
        let fractionalRaw = try makeJSON(#"{"messageId":"msg_1","createdAt":"2026-01-01T00:00:00.123Z"}"#)
        let fractionalMessage = try HightouchMessage(raw: fractionalRaw)
        XCTAssertNotNil(fractionalMessage.createdAt, "fractional timestamp should parse")

        let plainRaw = try makeJSON(#"{"messageId":"msg_1","createdAt":"2026-01-01T00:00:00Z"}"#)
        let plainMessage = try HightouchMessage(raw: plainRaw)
        XCTAssertNotNil(plainMessage.createdAt, "non-fractional timestamp should also parse")
    }

    func testExpiresAtAbsentIsNil() throws {
        let raw = try makeJSON(#"{"messageId":"msg_1","createdAt":"2026-08-01T12:00:00.000Z"}"#)
        let message = try HightouchMessage(raw: raw)
        XCTAssertNil(message.expiresAt)
    }

    func testMessagesISO8601ToleratesNumericEpoch() throws {
        let raw = try makeJSON(#"{"messageId":"msg_1","createdAt":1735689600}"#)
        let message = try HightouchMessage(raw: raw)
        XCTAssertEqual(message.createdAt, Date(timeIntervalSince1970: 1735689600))
    }

    // MARK: - messageType

    func testMessageTypeMissingIsNil() throws {
        let raw = try makeJSON(#"{"messageId":"msg_1"}"#)
        let message = try HightouchMessage(raw: raw)
        XCTAssertNil(message.messageType)
    }

    // MARK: - content.elements ordering

    func testContentElementsPreserveOrder() throws {
        let payloadString = """
        {"messageId":"msg_1","content":{"elements":[{"id":"1"},{"id":"2"},{"id":"3"}]}}
        """
        let raw = try makeJSON(payloadString)
        let message = try HightouchMessage(raw: raw)

        let ids = (0..<3).map { message.content?["elements"]?[$0]?["id"]?.stringValue }
        XCTAssertEqual(ids, ["1", "2", "3"])
    }

    // MARK: - customValues

    func testCustomValuesWithNestedObjectsArraysNumbersAndNullSurvive() throws {
        let payloadString = #"{"messageId":"msg_1","customValues":{"a":1,"b":[1,2,3],"c":{"d":"e"},"f":null}}"#
        let raw = try makeJSON(payloadString)
        let message = try HightouchMessage(raw: raw)

        let expectedCustomValues = try makeJSON(#"{"a":1,"b":[1,2,3],"c":{"d":"e"},"f":null}"#)
        XCTAssertEqual(message.customValues, expectedCustomValues)

        XCTAssertEqual(message.customValues?["a"]?.decimalValue, 1)
        XCTAssertEqual(message.customValues?["b"]?[2]?.decimalValue, 3)
        XCTAssertEqual(message.customValues?["c"]?["d"]?.stringValue, "e")
        XCTAssertEqual(message.customValues?["f"], .null)
    }

    // MARK: - priority

    func testPriorityDecodesEachLevel() throws {
        for level in HightouchMessagePriority.allCases {
            let raw = try makeJSON(#"{"messageId":"m","priority":"\#(level.rawValue)"}"#)
            XCTAssertEqual(try HightouchMessage(raw: raw).priority, level)
        }
    }

    func testPriorityMissingEmptyOrUnrecognizedIsDefault() throws {
        for payload in [
            #"{"messageId":"m"}"#,
            #"{"messageId":"m","priority":null}"#,
            #"{"messageId":"m","priority":""}"#,
            #"{"messageId":"m","priority":"urgent"}"#,
            #"{"messageId":"m","priority":"HIGH"}"#,
            #"{"messageId":"m","priority":1}"#,
        ] {
            XCTAssertEqual(try HightouchMessage(raw: makeJSON(payload)).priority, .default, payload)
        }
    }

    func testPriorityRanksHighMediumLowThenDefault() {
        let ranks = [HightouchMessagePriority.high, .medium, .low, .default].map(\.rank)
        XCTAssertEqual(ranks, ranks.sorted())
        XCTAssertEqual(Set(ranks).count, ranks.count)
    }

    func testPayloadDataIsByteStableAcrossEncodes() throws {
        let raw = try makeJSON(#"{"messageId":"m","zeta":1,"alpha":2,"middle":{"y":1,"x":2}}"#)
        let message = try HightouchMessage(raw: raw)

        let first = try message.payloadData()
        for _ in 0..<25 {
            XCTAssertEqual(try message.payloadData(), first)
        }
    }

    // MARK: - MessageOwner.current(analytics:)

    func testMessageOwnerCurrentPrefersUserId() {
        let analytics = Analytics(configuration: Configuration(writeKey: "\(name)-owner-userid"))
        analytics.identify(userId: "alice")

        XCTAssertEqual(MessageOwner.current(analytics: analytics), MessageOwner(kind: .userId, id: "alice"))
    }

    func testMessageOwnerCurrentFallsBackToAnonymousId() {
        let analytics = Analytics(configuration: Configuration(writeKey: "\(name)-owner-anon"))

        let anonymousId = analytics.anonymousId
        XCTAssertFalse(anonymousId.isEmpty, "precondition: a fresh Analytics instance always has an anonymousId")
        XCTAssertNil(analytics.userId, "precondition: no identify() call was made")

        XCTAssertEqual(MessageOwner.current(analytics: analytics), MessageOwner(kind: .anonymousId, id: anonymousId))
    }

    func testMessageOwnerCurrentReturnsNilWhenBothIdentifiersAreEmpty() {
        let writeKey = "\(name)-owner-empty"
        let suiteName = "com.hightouch.storage.\(writeKey)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set("", forKey: "hightouch.anonymousId")
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        let analytics = Analytics(configuration: Configuration(writeKey: writeKey))

        XCTAssertEqual(analytics.anonymousId, "", "precondition: the seeded empty anonymousId was read back")
        XCTAssertNil(analytics.userId, "precondition: no identify() call was made")

        XCTAssertNil(MessageOwner.current(analytics: analytics))
    }
}
