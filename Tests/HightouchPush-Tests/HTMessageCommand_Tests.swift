import XCTest
@testable import HightouchPush

// HightouchPushConfig holds delegates weakly; fakes are stored properties so they outlive each test.
final class HTMessageCommand_Tests: XCTestCase {

    // Drop references to the fakes so later tests don't inherit dangling weak delegates.

    func testParsesWithoutHightouchMessageId() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "command": ["verb": "syncMessages"],
            ] as [String: Any],
        ]

        let command = HTMessageCommand(userInfo)

        XCTAssertNotNil(command)
        XCTAssertEqual(command?.verb, .syncMessages)
        XCTAssertNil(command?.pushMessageId)
    }

    func testParsesWithHightouchMessageId() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "messageId": "01J8Z9K2QW3E4R5T6Y7U8I9O0P",
                "command": ["verb": "syncMessages"],
            ] as [String: Any],
        ]

        let command = HTMessageCommand(userInfo)

        XCTAssertNotNil(command)
        XCTAssertEqual(command?.verb, .syncMessages)
        XCTAssertEqual(command?.pushMessageId, "01J8Z9K2QW3E4R5T6Y7U8I9O0P")
    }

    // A disallowed scheme: this returns true only because urlDelegate short-circuits before the gate.

    func testNilWithoutHightouchKey() {
        let userInfo: [AnyHashable: Any] = ["aps": ["content-available": 1]]

        XCTAssertNil(HTMessageCommand(userInfo))
    }

    func testNilWhenCommandIsAbsent() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "messageId": "msg-1",
                "customData": ["foo": "bar"],
            ] as [String: Any],
        ]

        XCTAssertNil(HTMessageCommand(userInfo))
    }

    func testNilWhenVerbIsUnrecognized() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "command": ["verb": "someFutureVerb"],
            ] as [String: Any],
        ]

        XCTAssertNil(HTMessageCommand(userInfo))
    }

    func testNilWhenVerbKeyIsMissingEntirely() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "command": ["messageId": "msg_abc"],
            ] as [String: Any],
        ]

        XCTAssertNil(HTMessageCommand(userInfo))
    }

    // The server sends every inbox change, removals included, as `syncMessages`.
    func testDeleteMessageIsNotARecognizedVerb() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "command": ["verb": "deleteMessage", "messageId": "msg_abc"],
            ] as [String: Any],
        ]

        XCTAssertNil(HTMessageCommand(userInfo))
    }

    // MARK: - Advisory hints

    func testHintsAreParsedWhenWellFormed() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "command": [
                    "verb": "syncMessages",
                    "reason": "campaign_send",
                    "messageIds": ["m1", "m2"],
                    "locationIds": ["home_banner"],
                    "syncToken": "tok-123",
                ],
                "messageContext": ["executionId": "exec-1"],
            ] as [String: Any],
        ]

        let command = HTMessageCommand(userInfo)

        XCTAssertEqual(command?.reason, "campaign_send")
        XCTAssertEqual(command?.messageIds, ["m1", "m2"])
        XCTAssertEqual(command?.locationIds, ["home_banner"])
        XCTAssertEqual(command?.syncToken, "tok-123")
        XCTAssertEqual(command?.messageContext?["executionId"] as? String, "exec-1")
    }

    func testMalformedHintDegradesToNilWithoutFailingTheWholeParse() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "command": [
                    "verb": "syncMessages",
                    "messageIds": ["m1", 2, "m3"],
                ],
            ] as [String: Any],
        ]

        let command = HTMessageCommand(userInfo)

        XCTAssertNotNil(command, "a malformed advisory hint must not sink the whole parse")
        XCTAssertEqual(command?.verb, .syncMessages)
        XCTAssertNil(command?.messageIds)
    }

    func testAbsentHintsAreNilNotEmpty() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "command": ["verb": "syncMessages"],
            ] as [String: Any],
        ]

        let command = HTMessageCommand(userInfo)

        XCTAssertNil(command?.reason)
        XCTAssertNil(command?.messageIds)
        XCTAssertNil(command?.locationIds)
        XCTAssertNil(command?.syncToken)
        XCTAssertNil(command?.messageContext)
    }
}
