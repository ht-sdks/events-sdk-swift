import XCTest
@testable import HightouchPush
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class MessageStore_Expiry_Tests: XCTestCase {

    private func makeStore() throws -> MessageStore {
        try MessageStore(location: .ephemeral)
    }

    private func makeMessage(id: String, expiresAt: Date? = nil) throws -> HightouchMessage {
        var dict: [String: Any] = ["messageId": id]
        if let expiresAt = expiresAt {
            dict["expiresAt"] = ISO8601DateFormatter().string(from: expiresAt)
        }
        let raw = try JSON(dict)
        return try HightouchMessage(raw: raw)
    }

    @discardableResult
    private func replaceAllSync(
        _ store: MessageStore,
        _ messages: [HightouchMessage],
        owner: MessageOwner,
        now: Date = Date()
    ) throws -> UpsertOutcome {
        let expectation = expectation(description: "replaceAll")
        var outcome: Result<UpsertOutcome, Error>?
        store.replaceAll(messages, owner: owner, now: now) { result in
            outcome = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return try XCTUnwrap(outcome).get()
    }

    private func pruneSync(_ store: MessageStore, asOf now: Date) -> Int {
        let expectation = expectation(description: "pruneExpired")
        var pruned = 0
        store.pruneExpired(asOf: now) { count in
            pruned = count
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return pruned
    }

    private func totalRowCount(_ store: MessageStore) -> Int {
        var count = 0
        store.readContext.performAndWait {
            let fetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
            count = (try? store.readContext.count(for: fetch)) ?? 0
        }
        return count
    }

    // MARK: - Query-time filtering

    func testExpiredExcludedByDefaultIncludedWithFlag() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try replaceAllSync(store, try [
            makeMessage(id: "expired", expiresAt: now.addingTimeInterval(-60)),
            makeMessage(id: "future", expiresAt: now.addingTimeInterval(60))
        ], owner: owner)

        let defaultQuery = HightouchMessageQuery(now: now)
        let visible = store.messages(matching: defaultQuery, owner: owner)
        XCTAssertEqual(visible.map { $0.messageId }, ["future"])

        let includingExpired = HightouchMessageQuery(includeExpired: true, now: now)
        let all = store.messages(matching: includingExpired, owner: owner)
        XCTAssertEqual(Set(all.map { $0.messageId }), ["expired", "future"])
    }

    func testExpiresAtNilAlwaysIncluded() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try replaceAllSync(store, [try makeMessage(id: "never_expires", expiresAt: nil)], owner: owner)

        let visible = store.messages(matching: HightouchMessageQuery(now: now), owner: owner)
        XCTAssertEqual(visible.map { $0.messageId }, ["never_expires"])
    }

    func testBoundaryExpiresAtEqualToNowIsExpired() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try replaceAllSync(store, [try makeMessage(id: "boundary", expiresAt: now)], owner: owner)

        let visible = store.messages(matching: HightouchMessageQuery(now: now), owner: owner)
        XCTAssertTrue(visible.isEmpty, "expiresAt == now must count as expired")

        let count = store.count(matching: HightouchMessageQuery(now: now), owner: owner)
        XCTAssertEqual(count, 0)
    }

    // Give a stray duplicate notification a moment to arrive.

    func testPruneExpiredRemovesOnlyExpiredRowsAndReportsCount() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try replaceAllSync(store, try [
            makeMessage(id: "expired_1", expiresAt: now.addingTimeInterval(-60)),
            makeMessage(id: "expired_2", expiresAt: now.addingTimeInterval(-1)),
            makeMessage(id: "future", expiresAt: now.addingTimeInterval(60)),
            makeMessage(id: "never_expires", expiresAt: nil)
        ], owner: owner)

        let pruned = pruneSync(store, asOf: now)
        XCTAssertEqual(pruned, 2)
        XCTAssertEqual(totalRowCount(store), 2)
    }

    func testPruneBoundaryExpiresAtEqualToNowIsPruned() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try replaceAllSync(store, [try makeMessage(id: "boundary", expiresAt: now)], owner: owner)

        let pruned = pruneSync(store, asOf: now)
        XCTAssertEqual(pruned, 1)
        XCTAssertEqual(totalRowCount(store), 0)
    }

    func testPruneThenReadSeesTheDeletion() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try replaceAllSync(store, [try makeMessage(id: "expired", expiresAt: now.addingTimeInterval(-60))], owner: owner)

        var retained: HTMessageEntity!
        store.readContext.performAndWait {
            let fetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
            fetch.predicate = NSPredicate(
                format: "%K == %@ AND %K == %@",
                MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey,
                MessageStoreSchema.Attr.messageId.rawValue, "expired"
            )
            fetch.returnsObjectsAsFaults = false
            retained = try? store.readContext.fetch(fetch).first
        }
        XCTAssertNotNil(retained, "precondition: the row must already be registered in readContext before the prune runs")

        let pruned = pruneSync(store, asOf: now)
        XCTAssertEqual(pruned, 1)

        store.readContext.performAndWait {
            XCTAssertTrue(
                retained.isDeleted,
                "a row readContext already had registered before the prune must be marked deleted afterwards"
            )
        }

        XCTAssertNil(store.message(withId: "expired", owner: owner, includingExpired: true))
    }
}

private extension MessageStore {
    func message(withId messageId: String, owner: MessageOwner, includingExpired: Bool) -> HightouchMessage? {
        messages(matching: HightouchMessageQuery(includeExpired: includingExpired), owner: owner)
            .first { $0.messageId == messageId }
    }
}
#endif
