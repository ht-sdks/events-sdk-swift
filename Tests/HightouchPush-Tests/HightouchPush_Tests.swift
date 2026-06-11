import XCTest
@testable import HightouchPush
@testable import Hightouch

final class HightouchPush_Tests: XCTestCase {

    // MARK: - CepEventTracking.mergedProperties
    //
    // Precedence (highest wins): baseProperties > properties > messageContext.
    // baseProperties is whatever `CepEventTracking.baseProperties()` returns at
    // call time — these tests don't hard-code its keys, they read from it.

    func testMergeIncludesCallerProperties() {
        let merged = CepEventTracking.mergedProperties(
            properties: [
                "provider_event_type": CepEventTracking.pushOpened,
                "action": ["identifier": "default"],
            ],
            messageContext: [:]
        )

        XCTAssertEqual(merged["provider_event_type"] as? String, CepEventTracking.pushOpened)
        XCTAssertEqual((merged["action"] as? [String: String])?["identifier"], "default")
    }

    func testMergeLiftsMessageContextKeysToTopLevel() {
        let merged = CepEventTracking.mergedProperties(
            properties: [:],
            messageContext: [
                "messageId": "msg-1",
                "executionId": "exec-1",
                "sendId": "send-1",
                "parentModelPk": "pk-42",
                "hashedParentModelPk": "hashed-pk-42",
                "campaignId": "camp-1",
                "campaignRunId": "run-1",
            ]
        )

        // Each tracking field should be at the top level, not nested under
        // `_ht_message_context` (the legacy shape).
        XCTAssertNil(merged["_ht_message_context"])
        XCTAssertEqual(merged["messageId"] as? String, "msg-1")
        XCTAssertEqual(merged["executionId"] as? String, "exec-1")
        XCTAssertEqual(merged["sendId"] as? String, "send-1")
        XCTAssertEqual(merged["parentModelPk"] as? String, "pk-42")
        XCTAssertEqual(merged["hashedParentModelPk"] as? String, "hashed-pk-42")
        XCTAssertEqual(merged["campaignId"] as? String, "camp-1")
        XCTAssertEqual(merged["campaignRunId"] as? String, "run-1")
    }

    func testMergeAutoPicksUpNewMessageContextFields() {
        // If the push payload gains a new tracking field tomorrow, the SDK should
        // pick it up without code changes — the merge is generic over keys.
        let merged = CepEventTracking.mergedProperties(
            properties: [:],
            messageContext: ["futureField": "future-value"]
        )

        XCTAssertEqual(merged["futureField"] as? String, "future-value")
    }

    func testCallerPropertiesWinOverMessageContext() {
        // If messageContext happens to contain a key the caller also set, the
        // caller's value wins. Prevents a buggy/malicious payload from
        // impersonating fields like provider_event_type.
        let merged = CepEventTracking.mergedProperties(
            properties: [
                "provider_event_type": CepEventTracking.pushOpened,
                "action": ["identifier": "default"],
            ],
            messageContext: [
                "provider_event_type": "Fake Event",
                "action": ["identifier": "hijacked"],
                "messageId": "msg-1",
            ]
        )

        XCTAssertEqual(merged["provider_event_type"] as? String, CepEventTracking.pushOpened)
        XCTAssertEqual((merged["action"] as? [String: String])?["identifier"], "default")
        // Non-colliding keys still merge through.
        XCTAssertEqual(merged["messageId"] as? String, "msg-1")
    }

    func testBasePropertiesWinOverMessageContext() {
        // messageContext must not be able to stomp on system base properties.
        let baseKeys = CepEventTracking.baseProperties().keys
        var hijackContext: [String: Any] = ["messageId": "msg-1"]
        for key in baseKeys { hijackContext[key] = "hijacked-\(key)" }

        let merged = CepEventTracking.mergedProperties(
            properties: [:],
            messageContext: hijackContext
        )

        for (key, baseValue) in CepEventTracking.baseProperties() {
            XCTAssertEqual(
                String(describing: merged[key] ?? ""),
                String(describing: baseValue),
                "messageContext stomped on base property \(key)"
            )
        }
        XCTAssertEqual(merged["messageId"] as? String, "msg-1")
    }

    func testBasePropertiesWinOverCallerProperties() {
        // Symmetric to the above: even the caller can't override base.
        let baseKeys = CepEventTracking.baseProperties().keys
        var hijackProperties: [String: Any] = [:]
        for key in baseKeys { hijackProperties[key] = "hijacked-\(key)" }

        let merged = CepEventTracking.mergedProperties(
            properties: hijackProperties,
            messageContext: [:]
        )

        for (key, baseValue) in CepEventTracking.baseProperties() {
            XCTAssertEqual(
                String(describing: merged[key] ?? ""),
                String(describing: baseValue),
                "caller properties stomped on base property \(key)"
            )
        }
    }

    func testMergeWithEmptyMessageContextOnlyHasBaseAndCallerKeys() {
        let merged = CepEventTracking.mergedProperties(
            properties: ["provider_event_type": CepEventTracking.pushOpened],
            messageContext: [:]
        )

        XCTAssertNil(merged["messageId"])
        XCTAssertNil(merged["sendId"])
        XCTAssertNil(merged["_ht_message_context"])
    }
}
