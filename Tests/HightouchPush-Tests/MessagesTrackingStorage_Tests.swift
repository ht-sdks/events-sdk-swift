import XCTest
@testable import HightouchPush
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class MessagesTrackingStorage_Tests: XCTestCase {

    override func setUp() { super.setUp(); HightouchMessages.resetForTesting() }
    override func tearDown() { HightouchMessages.resetForTesting(); super.tearDown() }

    private func settle() {
        let e = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { e.fulfill() }
        wait(for: [e], timeout: 2)
    }

    private func setUpStore(id: String) throws -> (URL, MessageOwner) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("track-\(UUID().uuidString).sqlite")
        let owner = MessageOwner(kind: .userId, id: "alice")
        let store = try MessageStore(writeKey: "seed-\(UUID().uuidString)", location: .explicit(url))
        let raw = try JSON([
            "messageId": id, "locationId": "home",
            "messageContext": ["campaignRunId": "run_1"],
        ])
        let done = expectation(description: "seed")
        store.replaceAll([try HightouchMessage(raw: raw)], owner: owner) { _ in done.fulfill() }
        wait(for: [done], timeout: 5)

        let analytics = Analytics(configuration: Configuration(writeKey: "\(name)-\(UUID().uuidString)"))
        analytics.identify(userId: "alice")
        HightouchPush.initialize(analytics: analytics, config: HightouchPushConfig(appId: "app"))
        HightouchMessages.testStoreLocation = .explicit(url)
        HightouchMessages.initialize(analytics: analytics, config: HightouchMessagesConfig())
        return (url, owner)
    }

    func testTrackDisplayedDoesNotRemoveTheMessage() throws {
        _ = try setUpStore(id: "m1")
        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery()), 1)

        HightouchMessages.trackImpression(messageId: "m1")
        settle()

        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery()), 1,
                       "an impression must not delete the message it describes")
    }

    func testTrackDismissedRemovesTheMessageAndSuppressesResync() throws {
        let (_, owner) = try setUpStore(id: "m2")
        HightouchMessages.trackDismissed(messageId: "m2")
        settle()

        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery()), 0,
                       "a dismissal must delete the message")
        XCTAssertTrue(HightouchMessages.dismissedIds(owner: owner).contains("m2"),
                      "a dismissed message must not be re-inserted by the next sync")
    }

    func testClickStillHasAttributionAfterAnImpression() throws {
        _ = try setUpStore(id: "m3")
        HightouchMessages.trackImpression(messageId: "m3")
        settle()

        let ctx = HightouchMessages.messageContextForTesting(messageId: "m3")
        XCTAssertEqual(ctx["campaignRunId"] as? String, "run_1",
                       "attribution must survive an impression")
    }
}
#endif
