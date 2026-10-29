import XCTest
@testable import HightouchPush
import Hightouch

// MARK: - Outside the Core Data gate

final class HightouchMessages_Facade_UngatedTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HightouchMessages.resetForTesting()
    }

    func testPublicAPIDegradesToEmptyEverywhereTheCoreDataGateIsNotSatisfied() async {
        XCTAssertFalse(HightouchMessages.isInitialized)
        XCTAssertEqual(HightouchMessages.messages(matching: HightouchMessageQuery()), [])
        XCTAssertEqual(HightouchMessages.messages(locationId: "loc", variantSlug: "var", limit: 5), [])
        XCTAssertNil(HightouchMessages.message(withId: "anything"))
        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery()), 0)

        let completionExpectation = expectation(description: "loadMessages completion fires with an empty array")
        HightouchMessages.loadMessages(matching: HightouchMessageQuery()) { messages in
            XCTAssertEqual(messages, [])
            completionExpectation.fulfill()
        }
        wait(for: [completionExpectation], timeout: 2)

        let asyncMessages = await HightouchMessages.loadMessages(matching: HightouchMessageQuery())
        XCTAssertEqual(asyncMessages, [])
    }
}

// MARK: - Store-backed behavior

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class HightouchMessages_Facade_Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        HightouchMessages.resetForTesting()
    }

    override func tearDown() {
        HightouchMessages.resetForTesting()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    }

    @discardableResult
    private func seed(_ messages: [HightouchMessage], owner: MessageOwner, at url: URL) throws -> UpsertOutcome {
        let store = try MessageStore(location: .explicit(url))
        let seedExpectation = expectation(description: "seed replaceAll")
        var outcome: Result<UpsertOutcome, Error>?
        store.replaceAll(messages, owner: owner) { result in
            outcome = result
            seedExpectation.fulfill()
        }
        wait(for: [seedExpectation], timeout: 5)
        return try XCTUnwrap(outcome).get()
    }

    @discardableResult
    private func initializeFacade(at url: URL, userId: String) -> Analytics {
        let analytics = Analytics(configuration: Configuration(writeKey: "\(name)-\(UUID().uuidString)"))
        analytics.identify(userId: userId)
        HightouchMessages.testStoreLocation = .explicit(url)
        HightouchMessages.initialize(analytics: analytics, config: HightouchMessagesConfig())
        return analytics
    }

    // MARK: - Before initialize()

    func testEveryAPIBeforeInitializeReturnsEmptyAndDoesNotCrash() async {
        XCTAssertFalse(HightouchMessages.isInitialized)
        XCTAssertEqual(HightouchMessages.messages(matching: HightouchMessageQuery()), [])
        XCTAssertEqual(HightouchMessages.messages(locationId: "loc", variantSlug: "var", limit: 3), [])
        XCTAssertNil(HightouchMessages.message(withId: "anything"))
        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery()), 0)

        let completionExpectation = expectation(description: "loadMessages completion fires with an empty array")
        HightouchMessages.loadMessages(matching: HightouchMessageQuery()) { messages in
            XCTAssertEqual(messages, [])
            completionExpectation.fulfill()
        }
        wait(for: [completionExpectation], timeout: 2)

        let asyncMessages = await HightouchMessages.loadMessages(matching: HightouchMessageQuery())
        XCTAssertEqual(asyncMessages, [])
    }

    // MARK: - loadMessages identity

    func testLoadMessagesRefetchesWhenTheUserChangesBeforeDelivery() throws {
        let url = tempStoreURL()
        _ = try seed([try makeMessage(id: "alice_msg")], owner: MessageOwner(kind: .userId, id: "alice"), at: url)
        _ = try seed([try makeMessage(id: "bob_msg")], owner: MessageOwner(kind: .userId, id: "bob"), at: url)
        let analytics = initializeFacade(at: url, userId: "alice")

        let completed = expectation(description: "completion delivered")
        var delivered: [String] = []
        HightouchMessages.loadMessages(matching: HightouchMessageQuery()) { messages in
            delivered = messages.map(\.messageId)
            completed.fulfill()
        }
        // Alice's read has finished and its delivery is queued behind this test on main.
        HightouchMessages.queryQueue.sync {}
        analytics.identify(userId: "bob")
        wait(for: [completed], timeout: 5)

        XCTAssertEqual(delivered, ["bob_msg"], "a result read for the previous user must not be delivered")
    }

    // MARK: - loadMessages threading

    func testLoadMessagesDoesNotRunFetchOnTheCallingThread() throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        _ = try seed([try makeMessage(id: "m1", locationId: "home")], owner: owner, at: url)
        initializeFacade(at: url, userId: "alice")

        let completed = expectation(description: "completion delivered")
        var didReturn = false
        var completedOnMain = false
        var sawResult: [HightouchMessage] = []

        HightouchMessages.loadMessages(matching: HightouchMessageQuery(locationId: "home")) { messages in
            XCTAssertTrue(didReturn, "completion fired synchronously — the fetch ran on the calling thread")
            completedOnMain = Thread.isMainThread
            sawResult = messages
            completed.fulfill()
        }
        didReturn = true

        wait(for: [completed], timeout: 5)
        XCTAssertTrue(completedOnMain, "completion must arrive on the main queue")
        XCTAssertEqual(sawResult.map(\.messageId), ["m1"])
    }

    func testAsyncLoadMessagesReturnsSeededRows() async throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        _ = try seed([try makeMessage(id: "m1", locationId: "home")], owner: owner, at: url)
        initializeFacade(at: url, userId: "alice")

        let messages = await HightouchMessages.loadMessages(matching: HightouchMessageQuery(locationId: "home"))
        XCTAssertEqual(messages.map(\.messageId), ["m1"])
    }

    // MARK: - initialize() idempotency

    func testInitializeTwiceAtTheSameResolvedURLReusesTheSameStore() {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        HightouchMessages.testStoreLocation = .explicit(url)
        HightouchMessages.initialize(
            analytics: Analytics(configuration: Configuration(writeKey: "\(name)-1")),
            config: HightouchMessagesConfig()
        )
        let firstIdentity = HightouchMessages.openStoreIdentityForTesting
        XCTAssertNotNil(firstIdentity)

        HightouchMessages.initialize(
            analytics: Analytics(configuration: Configuration(writeKey: "\(name)-2")),
            config: HightouchMessagesConfig()
        )
        let secondIdentity = HightouchMessages.openStoreIdentityForTesting

        XCTAssertEqual(
            firstIdentity, secondIdentity,
            "a second initialize() at the same resolved store URL must reuse the open store, not open a second one over the same file"
        )
    }

    func testDifferentWriteKeysShareTheAppsOneStore() {
        HightouchMessages.initialize(
            analytics: Analytics(configuration: Configuration(writeKey: "\(name)-1")),
            config: HightouchMessagesConfig()
        )
        let firstIdentity = HightouchMessages.openStoreIdentityForTesting
        XCTAssertNotNil(firstIdentity)

        HightouchMessages.initialize(
            analytics: Analytics(configuration: Configuration(writeKey: "\(name)-2")),
            config: HightouchMessagesConfig()
        )

        XCTAssertEqual(
            firstIdentity, HightouchMessages.openStoreIdentityForTesting,
            "the store is per app, not per write key"
        )
    }

    // MARK: - Owner scoping / privacy

    func testQueriesOnlyReturnRowsForTheCurrentlyIdentifiedOwner() throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let alice = MessageOwner(kind: .userId, id: "alice-\(name)")
        let bob = MessageOwner(kind: .userId, id: "bob-\(name)")
        try seed([try makeMessage(id: "alice_msg")], owner: alice, at: url)
        try seed([try makeMessage(id: "bob_msg")], owner: bob, at: url)

        initializeFacade(at: url, userId: alice.id)

        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery()), 1)
        XCTAssertNil(HightouchMessages.message(withId: "bob_msg"), "bob's row must be invisible while alice is the identified owner")

        let visible = HightouchMessages.messages(matching: HightouchMessageQuery())
        XCTAssertEqual(visible.map { $0.messageId }, ["alice_msg"])

        let bobStore = try MessageStore(location: .explicit(url))
        XCTAssertEqual(
            bobStore.messages(matching: HightouchMessageQuery(), owner: bob).map(\.messageId),
            ["bob_msg"]
        )
    }

    // MARK: - locationId / variantSlug / limit through the convenience overload

    func testLocationVariantAndLimitFilterCorrectlyThroughTheFacade() throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let owner = MessageOwner(kind: .userId, id: "owner-\(name)")
        try seed([
            try makeMessage(id: "m1", locationId: "loc_a", variantSlug: "var_x"),
            try makeMessage(id: "m2", locationId: "loc_a", variantSlug: "var_y"),
            try makeMessage(id: "m3", locationId: "loc_b", variantSlug: "var_x"),
            try makeMessage(id: "m4", locationId: "loc_a", variantSlug: "var_x")
        ], owner: owner, at: url)

        initializeFacade(at: url, userId: owner.id)

        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery()), 4)
        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery(locationId: "loc_a")), 3)
        XCTAssertEqual(
            HightouchMessages.messageCount(matching: HightouchMessageQuery(locationId: "loc_a", variantSlug: "var_x")),
            2
        )

        let filtered = HightouchMessages.messages(locationId: "loc_a", variantSlug: "var_x")
        XCTAssertEqual(Set(filtered.map { $0.messageId }), ["m1", "m4"])

        let limited = HightouchMessages.messages(locationId: "loc_a", limit: 1)
        XCTAssertEqual(limited.count, 1)
        XCTAssertTrue(["m1", "m2", "m4"].contains(limited[0].messageId))

        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery()), 4, "reads must not remove rows")
    }

    // MARK: - messageCount agrees with messages

    func testMessageCountMatchesMessagesMatchingCount() throws {
        let url = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let owner = MessageOwner(kind: .userId, id: "owner-\(name)")
        let seeded = try (0..<7).map { try makeMessage(id: "m\($0)", locationId: $0 % 2 == 0 ? "loc_even" : "loc_odd") }
        try seed(seeded, owner: owner, at: url)

        initializeFacade(at: url, userId: owner.id)

        let evenQuery = HightouchMessageQuery(locationId: "loc_even")
        let evenCount = HightouchMessages.messageCount(matching: evenQuery)
        let evenMessages = HightouchMessages.messages(matching: evenQuery)
        XCTAssertEqual(evenCount, evenMessages.count)
        XCTAssertEqual(evenCount, 4, "m0, m2, m4, m6")

        let allCount = HightouchMessages.messageCount(matching: HightouchMessageQuery())
        let allMessages = HightouchMessages.messages(matching: HightouchMessageQuery())
        XCTAssertEqual(allCount, allMessages.count)
        XCTAssertEqual(allCount, 7, "the even read must not remove rows")
    }

    // MARK: - Change notification

    private final class RecordingMessagesDelegate: HightouchMessagesDelegate {
        var receivedChange: HightouchMessagesChange?
        var receivedOnMainThread = false
        var onChange: (() -> Void)?

        func hightouchMessagesDidChange(_ change: HightouchMessagesChange) {
            receivedChange = change
            receivedOnMainThread = Thread.isMainThread
            onChange?()
        }
    }

    func testNotifyChangeFiresTheDelegateAndPostsTheNotificationBothOnTheMainThread() {
        let delegate = RecordingMessagesDelegate()
        let delegateExpectation = expectation(description: "delegate called")
        delegate.onChange = { delegateExpectation.fulfill() }

        var config = HightouchMessagesConfig()
        config.delegate = delegate
        HightouchMessages.testStoreLocation = .ephemeral
        HightouchMessages.initialize(analytics: Analytics(configuration: Configuration(writeKey: "\(name)")), config: config)

        var notificationWasOnMainThread = false
        let notificationExpectation = expectation(forNotification: .hightouchMessagesDidChange, object: nil) { notification in
            notificationWasOnMainThread = Thread.isMainThread
            return (notification.userInfo?[HightouchMessages.changeUserInfoKey] as? HightouchMessagesChange) != nil
        }

        let change = HightouchMessagesChange(insertedIds: ["m1"], updatedIds: ["m2"], removedIds: ["m3"])
        HightouchMessages.notifyChange(change)

        wait(for: [delegateExpectation, notificationExpectation], timeout: 2)
        XCTAssertEqual(delegate.receivedChange?.insertedIds, ["m1"])
        XCTAssertEqual(delegate.receivedChange?.updatedIds, ["m2"])
        XCTAssertEqual(delegate.receivedChange?.removedIds, ["m3"])
        XCTAssertTrue(delegate.receivedOnMainThread, "the delegate must be called on the main thread")
        XCTAssertTrue(notificationWasOnMainThread, "the notification must be posted on the main thread")
    }

    func testWeaklyHeldDelegateWithNoStrongReferenceDoesNotCrashNotifyChange() {
        var config = HightouchMessagesConfig()
        do {
            let delegate = RecordingMessagesDelegate()
            config.delegate = delegate
        }

        HightouchMessages.testStoreLocation = .ephemeral
        HightouchMessages.initialize(analytics: Analytics(configuration: Configuration(writeKey: "\(name)")), config: config)

        let notificationExpectation = expectation(forNotification: .hightouchMessagesDidChange, object: nil, handler: nil)
        HightouchMessages.notifyChange(HightouchMessagesChange(insertedIds: ["m1"]))
        wait(for: [notificationExpectation], timeout: 2)
        // A mixed-type array fails the [String] cast but must not fail the init.
    }
}
#endif
