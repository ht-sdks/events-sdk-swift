import XCTest
import Hightouch
@testable import HightouchPush

final class HightouchMessagesActions_Tests: XCTestCase {

    private var output: OutputReaderPlugin!

    override func setUp() {
        super.setUp()
        HightouchMessages.resetForTesting()
    }

    override func tearDown() {
        HightouchMessages.isPushInitializedOverrideForTesting = nil
        HightouchMessages.resetForTesting()
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-actions-teardown"),
            config: HightouchPushConfig(appId: "actions-teardown")
        )
        output = nil
        super.tearDown()
    }

    private func initializePush() {
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-\(UUID().uuidString)"),
            config: HightouchPushConfig(appId: "actions-test-app")
        )
        let reader = OutputReaderPlugin()
        HightouchPush.analytics.add(plugin: reader)
        waitUntilStarted(analytics: HightouchPush.analytics)
        output = reader
    }

    private func engagementEvents() -> [TrackEvent] {
        output.events.compactMap { $0 as? TrackEvent }
            .filter { $0.event == CepEventTracking.engagementEvents }
    }

    // MARK: - trackClick

    func testTrackClickEmitsClickedOnTheInAppChannel() {
        initializePush()
        HightouchMessages.trackClick(messageId: "msg-1")

        let events = engagementEvents()
        XCTAssertEqual(events.count, 1)
        let props = events.last?.properties?.dictionaryValue
        XCTAssertEqual(props?["provider_event_type"] as? String, CepEventTracking.messageClicked)
        XCTAssertEqual(props?["message_id"] as? String, "msg-1")
        XCTAssertEqual(props?["channel_type"] as? String, "in_app")
        XCTAssertEqual(props?["_ht_cep_source"] as? String, "in_app_sdk")
    }

    func testTrackClickIdentifierDefaultsToDefault() {
        initializePush()
        HightouchMessages.trackClick(messageId: "msg-1")

        let action = engagementEvents().last?.properties?.dictionaryValue?["action"] as? [String: Any]
        XCTAssertEqual(action?["identifier"] as? String, "default")
        XCTAssertEqual(action?.count, 1)
    }

    func testTrackClickCarriesThePassedIdentifier() {
        initializePush()
        HightouchMessages.trackClick(messageId: "msg-1", identifier: "left-button")

        let action = engagementEvents().last?.properties?.dictionaryValue?["action"] as? [String: Any]
        XCTAssertEqual(action?["identifier"] as? String, "left-button")
        XCTAssertEqual(action?.count, 1)
    }

    func testTrackClickSendsNoElementOrActionTypeProperties() {
        initializePush()
        HightouchMessages.trackClick(messageId: "msg-1", identifier: "left-button")

        let props = engagementEvents().last?.properties?.dictionaryValue
        XCTAssertNotNil(props)
        for key in ["element_id", "element_tag", "type", "url"] {
            XCTAssertNil(props?[key], "\(key) must not be sent")
        }
        let action = props?["action"] as? [String: Any]
        XCTAssertNil(action?["type"])
        XCTAssertNil(action?["url"])
    }

    // MARK: - trackImpression / trackDismissed

    func testTrackDisplayedEmitsDisplayedOnInAppChannel() {
        initializePush()

        HightouchMessages.trackImpression(messageId: "msg-1")

        let props = engagementEvents().last?.properties?.dictionaryValue
        XCTAssertEqual(props?["provider_event_type"] as? String, CepEventTracking.messageDisplayed)
        XCTAssertEqual(props?["channel_type"] as? String, "in_app")
        XCTAssertEqual(props?["_ht_cep_source"] as? String, "in_app_sdk")
        XCTAssertEqual(props?["message_id"] as? String, "msg-1")
        XCTAssertNil(props?["action"])
    }

    func testTrackDismissedEmitsDismissedOnInAppChannel() {
        initializePush()

        HightouchMessages.trackDismissed(messageId: "msg-1")

        let props = engagementEvents().last?.properties?.dictionaryValue
        XCTAssertEqual(props?["provider_event_type"] as? String, CepEventTracking.messageDismissed)
        XCTAssertEqual(props?["channel_type"] as? String, "in_app")
        XCTAssertEqual(props?["message_id"] as? String, "msg-1")
        XCTAssertNil(props?["action"])
    }

    func testTrackingSkipsWithoutCrashingWhilePushIsTreatedAsUninitialized() {
        initializePush()
        HightouchMessages.isPushInitializedOverrideForTesting = false

        HightouchMessages.trackImpression(messageId: "msg-1")
        HightouchMessages.trackClick(messageId: "msg-1")
        HightouchMessages.trackClick(messageId: "msg-1", identifier: "left-button")
        HightouchMessages.trackDismissed(messageId: "msg-1")

        XCTAssertEqual(engagementEvents().count, 0, "no engagement event should fire while the guard treats push as uninitialized")
    }
}

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class HightouchMessagesActionsMessageContext_Tests: XCTestCase {

    private var output: OutputReaderPlugin!

    override func setUp() {
        super.setUp()
        HightouchMessages.resetForTesting()
    }

    override func tearDown() {
        HightouchMessages.resetForTesting()
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-actions-ctx-teardown"),
            config: HightouchPushConfig(appId: "actions-ctx-teardown")
        )
        output = nil
        super.tearDown()
    }

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    }

    @discardableResult
    private func seed(_ message: HightouchMessage, owner: MessageOwner, at url: URL) throws -> UpsertOutcome {
        let store = try MessageStore(location: .explicit(url))
        let seedExpectation = expectation(description: "seed replaceAll")
        var outcome: Result<UpsertOutcome, Error>?
        store.replaceAll([message], owner: owner) { result in
            outcome = result
            seedExpectation.fulfill()
        }
        wait(for: [seedExpectation], timeout: 5)
        return try XCTUnwrap(outcome).get()
    }

    private func initialize(storeAt url: URL, owner: MessageOwner) {
        let messagesAnalytics = Analytics(configuration: Configuration(writeKey: "\(name)-messages"))
        messagesAnalytics.identify(userId: owner.id)
        HightouchMessages.testStoreLocation = .explicit(url)
        var config = HightouchMessagesConfig()
        config.syncOnLaunch = false
        HightouchMessages.initialize(analytics: messagesAnalytics, config: config)

        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-\(UUID().uuidString)"),
            config: HightouchPushConfig(appId: "actions-ctx-app")
        )
        output = OutputReaderPlugin()
        HightouchPush.analytics.add(plugin: output)
        waitUntilStarted(analytics: HightouchPush.analytics)
    }

    private func engagementEvents() -> [TrackEvent] {
        output.events.compactMap { $0 as? TrackEvent }
            .filter { $0.event == CepEventTracking.engagementEvents }
    }

    private func contextMessage(id: String) throws -> HightouchMessage {
        try HightouchMessage(raw: try JSON([
            "messageId": id,
            "messageContext": [
                "executionId": "exec-1",
                "campaignId": "camp-1",
                "campaignRunId": "run-1",
            ],
        ]))
    }

    func testClickEventPicksUpPerMessageContextFromTheCachedMessage() throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let owner = MessageOwner(kind: .userId, id: "owner-\(name)")
        try seed(try contextMessage(id: "msg-ctx-1"), owner: owner, at: url)
        initialize(storeAt: url, owner: owner)

        HightouchMessages.trackClick(messageId: "msg-ctx-1")

        let props = engagementEvents().first?.properties?.dictionaryValue
        XCTAssertEqual(props?["executionId"] as? String, "exec-1")
        XCTAssertEqual(props?["campaignId"] as? String, "camp-1")
        XCTAssertEqual(props?["campaignRunId"] as? String, "run-1")
        XCTAssertEqual(props?["message_id"] as? String, "msg-ctx-1")
    }

    func testMissingMessageContextYieldsEmptyBagNotACrash() throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let owner = MessageOwner(kind: .userId, id: "owner-\(name)")
        try seed(try HightouchMessage(raw: try JSON(["messageId": "msg-no-ctx"])), owner: owner, at: url)
        initialize(storeAt: url, owner: owner)

        HightouchMessages.trackClick(messageId: "msg-no-ctx")

        let event = engagementEvents().first
        XCTAssertNotNil(event, "the click must still be recorded even with no messageContext bag to attach")
        XCTAssertEqual(event?.properties?.dictionaryValue?["message_id"] as? String, "msg-no-ctx")
    }

    func testTrackingAfterAReadStillCarriesMessageContext() throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let owner = MessageOwner(kind: .userId, id: "owner-\(name)")
        try seed(try contextMessage(id: "msg-read"), owner: owner, at: url)
        initialize(storeAt: url, owner: owner)

        XCTAssertEqual(HightouchMessages.messages(matching: HightouchMessageQuery()).map(\.messageId), ["msg-read"])
        XCTAssertNotNil(HightouchMessages.message(withId: "msg-read"))

        let removed = expectation(forNotification: .hightouchMessagesDidChange, object: nil) { note in
            let change = note.userInfo?[HightouchMessages.changeUserInfoKey] as? HightouchMessagesChange
            return change?.removedIds == ["msg-read"]
        }
        HightouchMessages.trackImpression(messageId: "msg-read")
        HightouchMessages.trackClick(messageId: "msg-read", identifier: "cta")
        HightouchMessages.trackDismissed(messageId: "msg-read")
        wait(for: [removed], timeout: 5)

        let events = engagementEvents()
        XCTAssertEqual(events.map { $0.properties?.dictionaryValue?["provider_event_type"] as? String }, [
            CepEventTracking.messageDisplayed, CepEventTracking.messageClicked, CepEventTracking.messageDismissed,
        ])
        for event in events {
            let props = event.properties?.dictionaryValue
            XCTAssertEqual(props?["executionId"] as? String, "exec-1")
            XCTAssertEqual(props?["campaignId"] as? String, "camp-1")
            XCTAssertEqual(props?["campaignRunId"] as? String, "run-1")
        }
    }
}
#endif
