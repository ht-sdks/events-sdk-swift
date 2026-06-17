import XCTest
@testable import HightouchPush

final class HTPushPayload_Tests: XCTestCase {

    // MARK: - HTPushPayload

    func testPayloadParsesFullPayload() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "messageId": "msg-123",
                "defaultAction": ["type": "openUrl", "data": "https://example.com"],
                "actionButtons": [
                    ["identifier": "btn1", "action": ["type": "openUrl", "data": "https://example.com/btn1"]],
                    ["identifier": "btn2", "action": ["type": "custom", "data": "payload"]],
                ],
            ] as [String: Any],
        ]

        let payload = HTPushPayload(userInfo)

        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.messageId, "msg-123")
        XCTAssertEqual(payload?.defaultAction?.type, "openUrl")
        XCTAssertEqual(payload?.defaultAction?.data, "https://example.com")
        XCTAssertEqual(payload?.actionButtons?.count, 2)
    }

    func testPayloadReturnsNilWithoutHightouchKey() {
        let userInfo: [AnyHashable: Any] = ["aps": ["alert": "Hello"]]

        let payload = HTPushPayload(userInfo)

        XCTAssertNil(payload)
    }

    func testPayloadReturnsNilWithoutMessageId() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [:] as [String: Any],
        ]

        let payload = HTPushPayload(userInfo)

        XCTAssertNil(payload)
    }

    func testPayloadHandlesMissingOptionalFields() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": ["messageId": "msg-123"] as [String: Any],
        ]

        let payload = HTPushPayload(userInfo)

        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.messageId, "msg-123")
        XCTAssertNil(payload?.defaultAction)
        XCTAssertNil(payload?.actionButtons)
        XCTAssertNil(payload?.customData)
    }

    func testPayloadParsesCustomData() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "messageId": "msg-123",
                "customData": ["promo_code": "SUMMER25", "variant": "A"],
            ] as [String: Any],
        ]

        let payload = HTPushPayload(userInfo)

        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.customData?["promo_code"], "SUMMER25")
        XCTAssertEqual(payload?.customData?["variant"], "A")
        XCTAssertEqual(payload?.customData?.count, 2)
    }

    func testPayloadCustomDataIsNilWhenAbsent() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": ["messageId": "msg-123"] as [String: Any],
        ]

        let payload = HTPushPayload(userInfo)

        XCTAssertNil(payload?.customData)
    }

    func testPayloadCustomDataIsNilForWrongType() {
        // customData must be [String: String]; a nested dict should not parse.
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "messageId": "msg-123",
                "customData": ["nested": ["key": "value"]],
            ] as [String: Any],
        ]

        let payload = HTPushPayload(userInfo)

        XCTAssertNil(payload?.customData)
    }

    // MARK: - HTActionButton

    func testActionButtonParsesValidDict() {
        let dict: [String: Any] = [
            "identifier": "btn1",
            "action": ["type": "openUrl", "data": "https://example.com"],
        ]

        let button = HTActionButton(dict)

        XCTAssertNotNil(button)
        XCTAssertEqual(button?.identifier, "btn1")
        XCTAssertEqual(button?.action?.type, "openUrl")
        XCTAssertEqual(button?.action?.data, "https://example.com")
    }

    func testActionButtonReturnsNilWithoutIdentifier() {
        let dict: [String: Any] = [
            "action": ["type": "openUrl", "data": "https://example.com"],
        ]

        let button = HTActionButton(dict)

        XCTAssertNil(button)
    }

    func testActionButtonHandlesMissingAction() {
        let dict: [String: Any] = ["identifier": "btn1"]

        let button = HTActionButton(dict)

        XCTAssertNotNil(button)
        XCTAssertEqual(button?.identifier, "btn1")
        XCTAssertNil(button?.action)
    }

    // MARK: - compactMap drops malformed buttons

    func testPayloadDropsMalformedActionButtons() {
        let userInfo: [AnyHashable: Any] = [
            "hightouch": [
                "messageId": "msg-123",
                "actionButtons": [
                    ["identifier": "valid", "action": ["type": "openUrl", "data": "https://example.com"]],
                    ["no_identifier": true],  // missing identifier — should be dropped
                    ["identifier": "also_valid"],
                ],
            ] as [String: Any],
        ]

        let payload = HTPushPayload(userInfo)

        XCTAssertEqual(payload?.actionButtons?.count, 2)
        XCTAssertEqual(payload?.actionButtons?[0].identifier, "valid")
        XCTAssertEqual(payload?.actionButtons?[1].identifier, "also_valid")
    }
}
