import XCTest
@testable import HightouchPush
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class MessagesReadAndDismiss_Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        HightouchMessages.resetForTesting()
    }

    override func tearDown() {
        HightouchMessages.resetForTesting()
        super.tearDown()
    }

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("read-dismiss-\(UUID().uuidString).sqlite")
    }

    private func makeMessage(id: String, locationId: String? = "home") throws -> HightouchMessage {
        var dict: [String: Any] = ["messageId": id]
        if let locationId = locationId { dict["locationId"] = locationId }
        return try HightouchMessage(raw: try JSON(dict))
    }

    @discardableResult
    private func seed(_ messages: [HightouchMessage], owner: MessageOwner, at url: URL) throws -> MessageStore {
        let store = try MessageStore(writeKey: "seed-\(UUID().uuidString)", location: .explicit(url))
        let done = expectation(description: "seed")
        var outcome: Result<UpsertOutcome, Error>?
        store.replaceAll(messages, owner: owner) { outcome = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        _ = try XCTUnwrap(outcome).get()
        return store
    }

    @discardableResult
    private func initializeFacade(at url: URL, userId: String) -> Analytics {
        let analytics = Analytics(configuration: Configuration(writeKey: "\(name)-\(UUID().uuidString)"))
        analytics.identify(userId: userId)
        HightouchMessages.testStoreLocation = .explicit(url)
        var config = HightouchMessagesConfig()
        config.syncOnLaunch = false
        HightouchMessages.initialize(analytics: analytics, config: config)
        return analytics
    }

    private func settle() {
        let waited = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { waited.fulfill() }
        wait(for: [waited], timeout: 2)
    }

    // MARK: - Reads don't remove

    func testRepeatedReadsReturnTheSameMessages() throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        try seed([try makeMessage(id: "m1"), try makeMessage(id: "m2")], owner: owner, at: url)
        initializeFacade(at: url, userId: "alice")

        XCTAssertEqual(HightouchMessages.messages(locationId: "home").map(\.messageId).sorted(), ["m1", "m2"])
        settle()

        XCTAssertEqual(HightouchMessages.messages(locationId: "home").map(\.messageId).sorted(), ["m1", "m2"])
        XCTAssertEqual(HightouchMessages.dismissedIds(owner: owner), [], "a read must not be logged")
    }

    func testMessageWithIdIsRepeatable() throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        try seed([try makeMessage(id: "m1")], owner: owner, at: url)
        initializeFacade(at: url, userId: "alice")

        XCTAssertEqual(HightouchMessages.message(withId: "m1")?.messageId, "m1")
        settle()

        XCTAssertEqual(HightouchMessages.message(withId: "m1")?.messageId, "m1")
        XCTAssertEqual(HightouchMessages.dismissedIds(owner: owner), [])
    }

    func testLoadMessagesDoesNotRemove() throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        try seed([try makeMessage(id: "m1")], owner: owner, at: url)
        initializeFacade(at: url, userId: "alice")

        let loaded = expectation(description: "loaded")
        var result: [HightouchMessage] = []
        HightouchMessages.loadMessages(matching: HightouchMessageQuery(locationId: "home")) {
            result = $0
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
        settle()

        XCTAssertEqual(result.map(\.messageId), ["m1"])
        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery(locationId: "home")), 1)
        XCTAssertEqual(HightouchMessages.dismissedIds(owner: owner), [])
    }

    func testAReadMessageSurvivesASync() throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let store = try seed([try makeMessage(id: "m1")], owner: owner, at: url)
        initializeFacade(at: url, userId: "alice")

        _ = HightouchMessages.messages(locationId: "home")
        settle()

        let resynced = expectation(description: "resync")
        store.replaceAll(
            [try makeMessage(id: "m1")],
            owner: owner,
            suppressing: { HightouchMessages.dismissedIds(owner: owner) }
        ) { _ in resynced.fulfill() }
        wait(for: [resynced], timeout: 5)

        XCTAssertEqual(HightouchMessages.messages(locationId: "home").map(\.messageId), ["m1"])
    }

    // MARK: - Dismissal removes and survives sync

    func testDismissDeletesLogsAndASyncDoesNotReinsert() throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let store = try seed([try makeMessage(id: "m1"), try makeMessage(id: "m2")], owner: owner, at: url)
        initializeFacade(at: url, userId: "alice")

        let removed = expectation(forNotification: .hightouchMessagesDidChange, object: nil) { note in
            let change = note.userInfo?[HightouchMessages.changeUserInfoKey] as? HightouchMessagesChange
            return change?.removedIds == ["m1"]
        }
        HightouchMessages.trackDismissed(messageId: "m1")
        wait(for: [removed], timeout: 5)

        XCTAssertNil(HightouchMessages.message(withId: "m1"))
        XCTAssertEqual(HightouchMessages.dismissedIds(owner: owner), ["m1"])

        let resynced = expectation(description: "resync")
        store.replaceAll(
            [try makeMessage(id: "m1"), try makeMessage(id: "m2")],
            owner: owner,
            suppressing: { HightouchMessages.dismissedIds(owner: owner) }
        ) { _ in resynced.fulfill() }
        wait(for: [resynced], timeout: 5)

        let remaining = store.messages(matching: HightouchMessageQuery(), owner: owner).map(\.messageId)
        XCTAssertEqual(remaining, ["m2"], "m1 was dismissed and must not come back")
    }

    func testWithoutSuppressionASyncDoesResurrectIt() throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let store = try seed([try makeMessage(id: "m1")], owner: owner, at: url)

        let deleted = expectation(description: "delete")
        store.delete(messageId: "m1", owner: owner) { _ in deleted.fulfill() }
        wait(for: [deleted], timeout: 5)
        XCTAssertEqual(store.messages(matching: HightouchMessageQuery(), owner: owner).count, 0)

        let resynced = expectation(description: "resync")
        store.replaceAll([try makeMessage(id: "m1")], owner: owner) { _ in resynced.fulfill() }
        wait(for: [resynced], timeout: 5)

        XCTAssertEqual(
            store.messages(matching: HightouchMessageQuery(), owner: owner).map(\.messageId),
            ["m1"],
            "a delete alone is undone by the next sync"
        )
    }

    // MARK: - Expiry

    func testExpiredMessageIsHiddenFromReadsAndPruned() throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let expired = try HightouchMessage(raw: try JSON([
            "messageId": "old", "locationId": "home", "expiresAt": "2000-01-01T00:00:00Z",
        ]))
        let store = try seed([expired, try makeMessage(id: "fresh")], owner: owner, at: url)
        initializeFacade(at: url, userId: "alice")

        XCTAssertEqual(HightouchMessages.messages(locationId: "home").map(\.messageId), ["fresh"])
        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery(locationId: "home")), 1)

        let pruned = expectation(description: "pruned")
        store.pruneExpired { _ in pruned.fulfill() }
        wait(for: [pruned], timeout: 5)

        let all = store.messages(matching: HightouchMessageQuery(includeExpired: true), owner: owner).map(\.messageId)
        XCTAssertEqual(all, ["fresh"])
        XCTAssertEqual(HightouchMessages.dismissedIds(owner: owner), [], "expiry is not a dismissal")
    }

    // MARK: - clearCachedMessages()

    func testClearRemovesEveryCachedMessageForTheCurrentIdentity() throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        try seed([try makeMessage(id: "m1"), try makeMessage(id: "m2")], owner: owner, at: url)
        initializeFacade(at: url, userId: "alice")

        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery()), 2)

        let cleared = expectation(description: "cleared")
        var removed = -1
        HightouchMessages.clearCachedMessages { removed = $0; cleared.fulfill() }
        wait(for: [cleared], timeout: 5)

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(HightouchMessages.messageCount(matching: HightouchMessageQuery()), 0)
    }

    func testClearForgetsDismissalsSoAResyncRepopulates() throws {
        let url = tempStoreURL()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let store = try seed([try makeMessage(id: "m1")], owner: owner, at: url)
        initializeFacade(at: url, userId: "alice")

        HightouchMessages.removeDismissed(messageId: "m1")
        settle()
        XCTAssertEqual(HightouchMessages.dismissedIds(owner: owner), ["m1"])

        let cleared = expectation(description: "cleared")
        HightouchMessages.clearCachedMessages { _ in cleared.fulfill() }
        wait(for: [cleared], timeout: 5)

        XCTAssertEqual(HightouchMessages.dismissedIds(owner: owner), [], "suppression must be forgotten too")

        let resynced = expectation(description: "resync")
        store.replaceAll(
            [try makeMessage(id: "m1")],
            owner: owner,
            suppressing: { HightouchMessages.dismissedIds(owner: owner) }
        ) { _ in resynced.fulfill() }
        wait(for: [resynced], timeout: 5)

        XCTAssertEqual(
            store.messages(matching: HightouchMessageQuery(), owner: owner).map(\.messageId),
            ["m1"],
            "after a clear, a resync must be able to bring the message back"
        )
    }

    func testClearIsScopedToTheCurrentIdentity() throws {
        let url = tempStoreURL()
        let alice = MessageOwner(kind: .userId, id: "alice")
        let bob = MessageOwner(kind: .userId, id: "bob")
        try seed([try makeMessage(id: "alice_msg")], owner: alice, at: url)
        let store = try seed([try makeMessage(id: "bob_msg")], owner: bob, at: url)
        initializeFacade(at: url, userId: "alice")

        let cleared = expectation(description: "cleared")
        HightouchMessages.clearCachedMessages { _ in cleared.fulfill() }
        wait(for: [cleared], timeout: 5)

        XCTAssertEqual(
            store.messages(matching: HightouchMessageQuery(), owner: bob).map(\.messageId),
            ["bob_msg"],
            "another identity's cache must survive"
        )
    }

    func testClearBeforeInitializeCompletesWithZeroAndDoesNotCrash() {
        let cleared = expectation(description: "cleared")
        var removed = -1
        HightouchMessages.clearCachedMessages { removed = $0; cleared.fulfill() }
        wait(for: [cleared], timeout: 5)
        XCTAssertEqual(removed, 0)
    }

    // MARK: - MessageDismissalLog

    func testDismissalIsScopedToOwner() {
        let defaults = UserDefaults(suiteName: "dismiss-scope-\(UUID().uuidString)")!
        let log = MessageDismissalLog(defaults: defaults)
        let alice = MessageOwner(kind: .userId, id: "alice")
        let anon = MessageOwner(kind: .anonymousId, id: "anon-1")

        log.record(messageIds: ["shared"], owner: alice)

        XCTAssertEqual(log.dismissedIds(owner: alice), ["shared"])
        XCTAssertEqual(log.dismissedIds(owner: anon), [], "one user's dismissal must not hide it from another")
    }

    func testRecordIsIdempotentAndPreservesOrder() {
        let defaults = UserDefaults(suiteName: "dismiss-idem-\(UUID().uuidString)")!
        let log = MessageDismissalLog(defaults: defaults)
        let owner = MessageOwner(kind: .userId, id: "alice")

        log.record(messageIds: ["a", "b"], owner: owner)
        log.record(messageIds: ["b", "c"], owner: owner)

        XCTAssertEqual(log.dismissedIds(owner: owner), ["a", "b", "c"], "no duplicate, order preserved")
    }

    func testLogEvictsOldestPastTheCap() {
        let defaults = UserDefaults(suiteName: "dismiss-cap-\(UUID().uuidString)")!
        let log = MessageDismissalLog(defaults: defaults)
        let owner = MessageOwner(kind: .userId, id: "alice")
        let limit = MessageDismissalLog.perOwnerLimit

        log.record(messageIds: (0...limit).map { "m\($0)" }, owner: owner)

        let stored = log.dismissedIds(owner: owner)
        XCTAssertEqual(stored.count, limit)
        XCTAssertFalse(stored.contains("m0"), "oldest evicted")
        XCTAssertTrue(stored.contains("m\(limit)"), "newest retained")
    }

    func testClearRemovesOnlyTheNamedOwner() {
        let defaults = UserDefaults(suiteName: "dismiss-clear-\(UUID().uuidString)")!
        let log = MessageDismissalLog(defaults: defaults)
        let alice = MessageOwner(kind: .userId, id: "alice")
        let bob = MessageOwner(kind: .userId, id: "bob")

        log.record(messageIds: ["a"], owner: alice)
        log.record(messageIds: ["b"], owner: bob)
        log.clear(owner: alice)

        XCTAssertEqual(log.dismissedIds(owner: alice), [])
        XCTAssertEqual(log.dismissedIds(owner: bob), ["b"])
    }
}
#endif
