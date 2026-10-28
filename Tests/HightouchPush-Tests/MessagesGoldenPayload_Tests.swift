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
          "priority": "1",
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

    func testGoldenPayloadPriorityRanksFirstNotLast() throws {
        let response = try MessagesFetchResponse.parse(XCTUnwrap(goldenPayload.data(using: .utf8)))
        let message = try XCTUnwrap(response.messages.first)

        XCTAssertEqual(message.priority, "1")
        XCTAssertEqual(message.priorityRank, 1)
        XCTAssertNotEqual(message.priorityRank, Int32.max, "a misspelled priority key would land here")
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
