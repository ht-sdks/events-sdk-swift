import XCTest
@testable import HightouchPush
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class MessagesGoldenPayload_Tests: XCTestCase {

    /// Not `HTMessageEntity(context:)`: `insertNewObject` resolves the entity through this context's coordinator.
    private let goldenPayload = """
    {
      "messages": [
        {
          "messageType": "embedded",
          "messageId": "msg_promo_two_button_001",
          "campaignId": "camp_coffee_launch",
          "createdAt": "2026-08-05T12:00:00.000Z",
          "expiresAt": "2099-09-05T12:00:00.000Z",
          "priority": "high",
          "locationId": "home_promo",
          "triggerType": "immediate",
          "customValues": { "roastLevel": "medium", "featured": true },
          "version": "1",
          "variantSlug": "two-button",
          "messageContext": {
            "executionId": "exec_001",
            "sendId": "send_001",
            "campaignId": "camp_coffee_launch",
            "campaignRunId": "run_001"
          },
          "content": {
            "html": "",
            "elements": [
              {
                "id": "1",
                "tag": "background",
                "elementType": "image",
                "order": null,
                "mediaUrl": "https://hqcoffe.com/beans.jpg",
                "mediaCaption": "HQ beans",
                "text": null
              },
              {
                "id": "2",
                "tag": "title",
                "elementType": "text",
                "order": null,
                "mediaUrl": null,
                "mediaCaption": null,
                "text": "Grown in Brazil, roasted stateside."
              },
              {
                "id": "3",
                "tag": "left-button",
                "elementType": "button",
                "order": null,
                "mediaUrl": null,
                "mediaCaption": null,
                "text": "Order now"
              },
              {
                "id": "4",
                "tag": "right-button",
                "elementType": "button",
                "order": null,
                "mediaUrl": null,
                "mediaCaption": null,
                "text": "Learn more"
              }
            ]
          }
        }
      ]
    }
    """

    func testGoldenPayloadParsesWithNoMalformedRows() throws {
        let response = try MessagesFetchResponse.parse(XCTUnwrap(goldenPayload.data(using: .utf8)))

        XCTAssertEqual(response.malformedCount, 0)
        XCTAssertEqual(response.messages.count, 1)

        let message = try XCTUnwrap(response.messages.first)
        XCTAssertEqual(message.messageId, "msg_promo_two_button_001")
        XCTAssertEqual(message.messageType, "embedded")
        XCTAssertEqual(message.campaignId, "camp_coffee_launch")
        XCTAssertEqual(message.locationId, "home_promo")
        XCTAssertEqual(message.variantSlug, "two-button")
        XCTAssertEqual(message.triggerType, "immediate")
        XCTAssertEqual(message.version, "1")
        XCTAssertNotNil(message.createdAt)
        XCTAssertNotNil(message.expiresAt)
    }

    func testGoldenPayloadPriorityDecodes() throws {
        let response = try MessagesFetchResponse.parse(XCTUnwrap(goldenPayload.data(using: .utf8)))
        let message = try XCTUnwrap(response.messages.first)

        XCTAssertEqual(message.priority, .high)
    }

    func testGoldenPayloadPreservesContentAndCustomValues() throws {
        let response = try MessagesFetchResponse.parse(XCTUnwrap(goldenPayload.data(using: .utf8)))
        let message = try XCTUnwrap(response.messages.first)

        let elements = try XCTUnwrap(message.content?["elements"]?.arrayValue)
        XCTAssertEqual(elements.count, 4)

        let tags = (0..<4).map { message.content?["elements"]?[$0]?["tag"]?.stringValue }
        XCTAssertEqual(tags, ["background", "title", "left-button", "right-button"])

        XCTAssertEqual(message.content?["elements"]?[2]?["text"]?.stringValue, "Order now")

        XCTAssertEqual(message.content?["html"]?.stringValue, "")

        XCTAssertEqual(message.customValues?["roastLevel"]?.stringValue, "medium")
        XCTAssertEqual(message.customValues?["featured"]?.boolValue, true)

        XCTAssertEqual(message.raw["messageContext"]?["campaignRunId"]?.stringValue, "run_001")
    }

    func testGoldenPayloadStoresAndIsQueryableByLocationAndVariant() throws {
        let response = try MessagesFetchResponse.parse(XCTUnwrap(goldenPayload.data(using: .utf8)))
        let store = try MessageStore(location: .ephemeral)
        let owner = MessageOwner(kind: .userId, id: "alice")

        let stored = expectation(description: "replaceAll")
        var outcome: Result<UpsertOutcome, Error>?
        store.replaceAll(response.messages, owner: owner) { result in
            outcome = result
            stored.fulfill()
        }
        wait(for: [stored], timeout: 5)
        XCTAssertEqual(try XCTUnwrap(outcome).get().insertedIds, ["msg_promo_two_button_001"])

        let byLocation = store.messages(matching: HightouchMessageQuery(locationId: "home_promo"), owner: owner)
        XCTAssertEqual(byLocation.map(\.messageId), ["msg_promo_two_button_001"])

        let byBoth = store.messages(
            matching: HightouchMessageQuery(locationId: "home_promo", variantSlug: "two-button"),
            owner: owner
        )
        XCTAssertEqual(byBoth.count, 1)

        let elements = try XCTUnwrap(byBoth.first?.content?["elements"]?.arrayValue)
        XCTAssertEqual(elements.count, 4)
    }

    // MARK: - Json elements

    private static func embeddedMessage(id: String, elements: String) -> String {
        """
        {
          "messages": [
            {
              "messageType": "embedded",
              "messageId": "\(id)",
              "campaignId": "camp_coffee_launch",
              "createdAt": "2026-08-05T12:00:00.000Z",
              "expiresAt": "2099-09-05T12:00:00.000Z",
              "locationId": "home_promo",
              "version": "1",
              "variantSlug": "promo_banner",
              "content": { "elements": \(elements) }
            }
          ]
        }
        """
    }

    private let jsonObjectPayload = MessagesGoldenPayload_Tests.embeddedMessage(
        id: "msg_json_object_001",
        elements: """
        [
          { "tag": "title", "elementType": "Text", "text": "Hi Ada" },
          {
            "tag": "style",
            "elementType": "Json",
            "json": {
              "label": "{{ first_name }}",
              "sizes": [8, 12],
              "color": "#DD0031",
              "nested": { "stray": [1, null] }
            }
          }
        ]
        """
    )

    private let jsonArrayPayload = MessagesGoldenPayload_Tests.embeddedMessage(
        id: "msg_json_array_001",
        elements: """
        [
          { "tag": "style", "elementType": "Json", "json": [1, "two"] },
          { "tag": "corners", "elementType": "Json", "json": [{ "radius": 8 }] },
          { "tag": "greeting", "elementType": "Json", "json": [{ "greeting": "Hi Ada", "sizes": [8, null, true] }] }
        ]
        """
    )

    private func storeAndReadBack(
        _ message: HightouchMessage,
        in store: MessageStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HightouchMessage {
        let owner = MessageOwner(kind: .userId, id: "alice")
        let first = try replaceAllSync(store, [message], owner: owner)
        XCTAssertEqual(first.insertedIds, [message.messageId], file: file, line: line)
        return try XCTUnwrap(store.message(withId: message.messageId, owner: owner), file: file, line: line)
    }

    func testJsonObjectElementReachesTheAppAsParsedJson() throws {
        let response = try MessagesFetchResponse.parse(XCTUnwrap(jsonObjectPayload.data(using: .utf8)))
        XCTAssertEqual(response.malformedCount, 0)
        let message = try XCTUnwrap(response.messages.first)

        let expectedContent: JSON = .object([
            "elements": .array([
                .object(["tag": .string("title"), "elementType": .string("Text"), "text": .string("Hi Ada")]),
                .object([
                    "tag": .string("style"),
                    "elementType": .string("Json"),
                    "json": .object([
                        "label": .string("{{ first_name }}"),
                        "sizes": .array([.number(8), .number(12)]),
                        "color": .string("#DD0031"),
                        "nested": .object(["stray": .array([.number(1), .null])])
                    ])
                ])
            ])
        ])
        XCTAssertEqual(message.content, expectedContent)

        let style = try XCTUnwrap(message.content?["elements"]?[1])
        XCTAssertEqual(style["elementType"]?.stringValue, "Json")
        XCTAssertNil(style["text"], "a Json element carries its value under `json`, not `text`")
        XCTAssertEqual(style["json"]?["label"]?.stringValue, "{{ first_name }}")
        XCTAssertEqual(style["json"]?["sizes"]?[1]?.intValue, 12)

        let stored = try storeAndReadBack(message, in: try makeStore())
        XCTAssertEqual(stored.content, expectedContent)
        XCTAssertEqual(stored.raw, message.raw)
    }

    func testJsonArrayElementReachesTheAppAsParsedJson() throws {
        let response = try MessagesFetchResponse.parse(XCTUnwrap(jsonArrayPayload.data(using: .utf8)))
        XCTAssertEqual(response.malformedCount, 0)
        let message = try XCTUnwrap(response.messages.first)

        let expectedContent: JSON = .object([
            "elements": .array([
                .object([
                    "tag": .string("style"),
                    "elementType": .string("Json"),
                    "json": .array([.number(1), .string("two")])
                ]),
                .object([
                    "tag": .string("corners"),
                    "elementType": .string("Json"),
                    "json": .array([.object(["radius": .number(8)])])
                ]),
                .object([
                    "tag": .string("greeting"),
                    "elementType": .string("Json"),
                    "json": .array([
                        .object([
                            "greeting": .string("Hi Ada"),
                            "sizes": .array([.number(8), .null, .bool(true)])
                        ])
                    ])
                ])
            ])
        ])
        XCTAssertEqual(message.content, expectedContent)
        XCTAssertEqual(message.content?["elements"]?[0]?["json"]?[1]?.stringValue, "two")

        let stored = try storeAndReadBack(message, in: try makeStore())
        XCTAssertEqual(stored.content, expectedContent)
        XCTAssertEqual(stored.raw, message.raw)
    }

    func testResyncingAJsonElementReportsNoChange() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let data = try XCTUnwrap(jsonObjectPayload.data(using: .utf8))

        try replaceAllSync(store, MessagesFetchResponse.parse(data).messages, owner: owner)
        let second = try replaceAllSync(store, MessagesFetchResponse.parse(data).messages, owner: owner)

        XCTAssertEqual(second.unchanged, 1, "an object's key order must not make a re-fetched message look updated")
        XCTAssertEqual(second.updatedIds, [])
    }

    func testJsonNumbersUpToTheBackendMaximumSurviveStorage() throws {
        let payload = MessagesGoldenPayload_Tests.embeddedMessage(
            id: "msg_json_numbers_001",
            elements: """
            [{ "tag": "limits", "elementType": "Json", "json": [9007199254740991, -9007199254740991, 0.1] }]
            """
        )
        let message = try XCTUnwrap(MessagesFetchResponse.parse(XCTUnwrap(payload.data(using: .utf8))).messages.first)
        let stored = try storeAndReadBack(message, in: try makeStore())

        let numbers = try XCTUnwrap(stored.content?["elements"]?[0]?["json"])
        XCTAssertEqual(numbers[0]?.decimalValue, Decimal(string: "9007199254740991"))
        XCTAssertEqual(numbers[1]?.decimalValue, Decimal(string: "-9007199254740991"))
        XCTAssertEqual(numbers[2]?.decimalValue, Decimal(string: "0.1"))
    }

    func testJsonElementAtTheBackendNestingLimitSurvivesStorage() throws {
        let depth = 20
        let nested = String(repeating: #"{"level":"#, count: depth - 1) + #"["leaf"]"# + String(repeating: "}", count: depth - 1)
        let payload = MessagesGoldenPayload_Tests.embeddedMessage(
            id: "msg_json_deep_001",
            elements: #"[{ "tag": "tree", "elementType": "Json", "json": \#(nested) }]"#
        )
        let message = try XCTUnwrap(MessagesFetchResponse.parse(XCTUnwrap(payload.data(using: .utf8))).messages.first)
        let stored = try storeAndReadBack(message, in: try makeStore())

        var node = try XCTUnwrap(stored.content?["elements"]?[0]?["json"])
        for _ in 0..<(depth - 1) {
            node = try XCTUnwrap(node["level"])
        }
        XCTAssertEqual(node[0]?.stringValue, "leaf")
    }

    func testJsonElementNearTheInboxItemLimitSurvivesAStoreReopen() throws {
        let rows = (0..<3150).map { index in
            #"{"sku":"sku_\#(index)","label":"\#(String(repeating: "x", count: 64))","price":\#(index).5,"tags":["a","b"]}"#
        }
        let payload = MessagesGoldenPayload_Tests.embeddedMessage(
            id: "msg_json_large_001",
            elements: #"[{ "tag": "catalog", "elementType": "Json", "json": { "rows": [\#(rows.joined(separator: ","))] } }]"#
        )
        let data = try XCTUnwrap(payload.data(using: .utf8))
        // The inbox stores a message as one item of at most 400 KB.
        XCTAssertGreaterThan(data.count, 390_000)
        XCTAssertLessThanOrEqual(data.count, 400_000)

        let response = try MessagesFetchResponse.parse(data)
        XCTAssertEqual(response.malformedCount, 0)
        let message = try XCTUnwrap(response.messages.first)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("messages.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = MessageOwner(kind: .userId, id: "alice")

        do {
            let store = try MessageStore(location: .explicit(url))
            _ = try storeAndReadBack(message, in: store)
        }

        let reopened = try MessageStore(location: .explicit(url))
        let stored = try XCTUnwrap(reopened.message(withId: "msg_json_large_001", owner: owner))
        XCTAssertEqual(stored.raw, message.raw)
        XCTAssertEqual(try stored.payloadData(), try message.payloadData())

        let storedRows = stored.content?["elements"]?[0]?["json"]?["rows"]
        XCTAssertEqual(storedRows?.arrayValue?.count, 3150)
        XCTAssertEqual(storedRows?[3149]?["sku"]?.stringValue, "sku_3149")
        XCTAssertEqual(storedRows?[3149]?["price"]?.decimalValue, Decimal(string: "3149.5"))
    }

    // MARK: - Boolean condition

    private let conditionOnPayload = MessagesGoldenPayload_Tests.embeddedMessage(
        id: "msg_condition_001",
        elements: """
        [
          { "tag": "headline", "elementType": "Text", "text": "Sale" },
          { "tag": "is_holiday", "elementType": "BooleanCondition", "text": "true" },
          { "tag": "holiday_banner", "elementType": "Text", "text": "Happy holidays" },
          { "tag": "snow", "elementType": "Toggle", "text": "true" },
          { "tag": "footer", "elementType": "Text", "text": "Ends Sunday" }
        ]
        """
    )

    private let conditionOffPayload = MessagesGoldenPayload_Tests.embeddedMessage(
        id: "msg_condition_001",
        elements: """
        [
          { "tag": "headline", "elementType": "Text", "text": "Sale" },
          { "tag": "footer", "elementType": "Text", "text": "Ends Sunday" }
        ]
        """
    )

    private func element(_ tag: String, in message: HightouchMessage) -> JSON? {
        guard case .array(let elements)? = message.content?["elements"] else { return nil }
        return elements.first { $0["tag"]?.stringValue == tag }
    }

    private func tags(in message: HightouchMessage) -> [String?] {
        guard case .array(let elements)? = message.content?["elements"] else { return [] }
        return elements.map { $0["tag"]?.stringValue }
    }

    func testBooleanConditionOnSendsItsElementAndItsFieldsAsSiblings() throws {
        let response = try MessagesFetchResponse.parse(XCTUnwrap(conditionOnPayload.data(using: .utf8)))
        XCTAssertEqual(response.malformedCount, 0)
        let message = try XCTUnwrap(response.messages.first)
        let stored = try storeAndReadBack(message, in: try makeStore())

        XCTAssertEqual(tags(in: stored), ["headline", "is_holiday", "holiday_banner", "snow", "footer"])
        XCTAssertEqual(
            element("is_holiday", in: stored),
            .object(["tag": .string("is_holiday"), "elementType": .string("BooleanCondition"), "text": .string("true")])
        )
        XCTAssertEqual(element("holiday_banner", in: stored)?["text"]?.stringValue, "Happy holidays")
        XCTAssertEqual(element("snow", in: stored)?["text"]?.stringValue, "true")
        XCTAssertEqual(stored.raw, message.raw)
    }

    func testBooleanConditionOffOmitsItsElementAndItsFields() throws {
        let response = try MessagesFetchResponse.parse(XCTUnwrap(conditionOffPayload.data(using: .utf8)))
        XCTAssertEqual(response.malformedCount, 0)
        let message = try XCTUnwrap(response.messages.first)
        let stored = try storeAndReadBack(message, in: try makeStore())

        XCTAssertEqual(tags(in: stored), ["headline", "footer"])
        for absent in ["is_holiday", "holiday_banner", "snow"] {
            XCTAssertNil(element(absent, in: stored), absent)
        }
        XCTAssertEqual(element("footer", in: stored)?["text"]?.stringValue, "Ends Sunday")
        XCTAssertEqual(stored.raw, message.raw)
    }

    func testTurningABooleanConditionOffRemovesItsElementsFromTheStoredMessage() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let on = try MessagesFetchResponse.parse(XCTUnwrap(conditionOnPayload.data(using: .utf8))).messages
        let off = try MessagesFetchResponse.parse(XCTUnwrap(conditionOffPayload.data(using: .utf8))).messages

        try replaceAllSync(store, on, owner: owner)
        let outcome = try replaceAllSync(store, off, owner: owner)

        XCTAssertEqual(outcome.updatedIds, ["msg_condition_001"], "the app is only told to re-render when the message is reported as updated")
        let stored = try XCTUnwrap(store.message(withId: "msg_condition_001", owner: owner))
        XCTAssertEqual(tags(in: stored), ["headline", "footer"])
    }

    // 200 messages per chunk.

    func testBareObjectEnvelopeThrowsRatherThanParsingAsEmpty() throws {
        let bareObject = try XCTUnwrap(#"{"messageId":"msg_1","variantSlug":"two-button"}"#.data(using: .utf8))
        XCTAssertThrowsError(try MessagesFetchResponse.parse(bareObject), "an empty parse would wipe the owner's cache") {
            XCTAssertTrue($0 is MissingMessagesArrayError)
        }
    }

    func testNullOrNonArrayMessagesThrows() throws {
        for body in [#"{"messages":null}"#, #"{"messages":{}}"#, #""messages""#, "42"] {
            XCTAssertThrowsError(try MessagesFetchResponse.parse(XCTUnwrap(body.data(using: .utf8))), body)
        }
    }

    func testEmptyMessagesArrayIsAnAuthoritativeEmptySet() throws {
        let response = try MessagesFetchResponse.parse(XCTUnwrap(#"{"messages":[]}"#.data(using: .utf8)))
        XCTAssertEqual(response.messages.count, 0)
        XCTAssertEqual(response.malformedCount, 0)
    }

    func testEmptyMessageIdIsDroppedAsMalformed() throws {
        let emptyId = #"{"messages":[{"messageId":"","variantSlug":"two-button"}]}"#
        let response = try MessagesFetchResponse.parse(XCTUnwrap(emptyId.data(using: .utf8)))

        XCTAssertEqual(response.messages.count, 0)
        XCTAssertEqual(response.malformedCount, 1, "at least this one is reported")
    }
}
#endif
