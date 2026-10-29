import XCTest
@testable import HightouchPush
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class MessageStore_Upsert_Tests: XCTestCase {

    // MARK: - Fixtures

    private static func makeBareEntity(in context: NSManagedObjectContext) -> HTMessageEntity {
        NSEntityDescription.insertNewObject(forEntityName: MessageStoreSchema.entityName, into: context) as! HTMessageEntity
    }

    private func makeJSON(_ jsonString: String) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: Data(jsonString.utf8))
    }

    @discardableResult
    private func enforceLimitSync(_ store: MessageStore, maxStoredMessages: Int, preserving owner: MessageOwner? = nil) -> Int {
        let expectation = expectation(description: "enforceLimit")
        var evicted = 0
        store.enforceLimit(maxStoredMessages: maxStoredMessages, preserving: owner) { count in
            evicted = count
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return evicted
    }

    private struct RowSnapshot {
        let insertedAt: Date
        let payload: Data
    }

    private func snapshot(_ store: MessageStore, id: String, owner: MessageOwner) -> RowSnapshot? {
        var result: RowSnapshot?
        store.readContext.performAndWait {
            let fetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
            fetch.predicate = NSPredicate(
                format: "%K == %@ AND %K == %@",
                MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey,
                MessageStoreSchema.Attr.messageId.rawValue, id
            )
            if let entity = try? store.readContext.fetch(fetch).first {
                result = RowSnapshot(insertedAt: entity.insertedAt, payload: entity.payload)
            }
        }
        return result
    }

    // MARK: - Insert / update / unchanged

    func testChangedContentRewritesPayloadButKeepsInsertedAt() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(60)

        try replaceAllSync(store, [try makeMessage(id: "m1", campaignId: "camp_1")], owner: owner, now: t0)
        let firstSnapshot = try XCTUnwrap(snapshot(store, id: "m1", owner: owner))
        XCTAssertEqual(firstSnapshot.insertedAt, t0)

        let outcome = try replaceAllSync(store, [try makeMessage(id: "m1", campaignId: "camp_2")], owner: owner, now: t1)
        XCTAssertEqual(outcome.updatedIds, ["m1"])
        XCTAssertEqual(outcome.unchanged, 0)

        let secondSnapshot = try XCTUnwrap(snapshot(store, id: "m1", owner: owner))
        XCTAssertEqual(secondSnapshot.insertedAt, t0, "insertedAt must not move on an update")
        XCTAssertNotEqual(secondSnapshot.payload, firstSnapshot.payload, "payload must be rewritten on real content change")
    }

    func testByteIdenticalReUpsertReportsUnchangedAndKeepsTheRow() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(60)
        let message = try makeMessage(id: "m1", campaignId: "camp_1")

        try replaceAllSync(store, [message], owner: owner, now: t0)
        let beforeSnapshot = try XCTUnwrap(snapshot(store, id: "m1", owner: owner))
        let outcome = try replaceAllSync(store, [message], owner: owner, now: t1)

        XCTAssertEqual(outcome.unchanged, 1)
        XCTAssertTrue(outcome.updatedIds.isEmpty)
        XCTAssertTrue(outcome.insertedIds.isEmpty)

        let afterSnapshot = try XCTUnwrap(snapshot(store, id: "m1", owner: owner))
        XCTAssertEqual(afterSnapshot.insertedAt, beforeSnapshot.insertedAt)
        XCTAssertEqual(afterSnapshot.payload, beforeSnapshot.payload)
    }

    // Fired while the write is likely still in flight; only asserts each read sees a consistent snapshot.
    func testKeyOrderDifferencesInEquivalentPayloadsDoNotCountAsChanged() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(60)

        let firstOrder = try HightouchMessage(raw: try makeJSON(#"{"messageId":"m1","campaignId":"camp_1"}"#))
        let secondOrder = try HightouchMessage(raw: try makeJSON(#"{"campaignId":"camp_1","messageId":"m1"}"#))
        XCTAssertEqual(firstOrder, secondOrder, "precondition: these two values must be semantically equal")

        try replaceAllSync(store, [firstOrder], owner: owner, now: t0)
        let beforeSnapshot = try XCTUnwrap(snapshot(store, id: "m1", owner: owner))
        let outcome = try replaceAllSync(store, [secondOrder], owner: owner, now: t1)

        XCTAssertEqual(outcome.unchanged, 1)
        XCTAssertTrue(outcome.updatedIds.isEmpty)

        let afterSnapshot = try XCTUnwrap(snapshot(store, id: "m1", owner: owner))
        XCTAssertEqual(afterSnapshot.payload, beforeSnapshot.payload)
    }

    func testDuplicateIdsInOneInputLastWins() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")

        let first = try makeMessage(id: "dup", campaignId: "camp_first")
        let last = try makeMessage(id: "dup", campaignId: "camp_last")

        let outcome = try replaceAllSync(store, [first, last], owner: owner)
        XCTAssertEqual(outcome.insertedIds, ["dup"])

        let stored = try XCTUnwrap(store.message(withId: "dup", owner: owner))
        XCTAssertEqual(stored.campaignId, "camp_last")
    }

    // MARK: - Chunking

    func test1000MessagesAcrossThe200ChunkBoundaryAllLand() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")

        let messages = try (0..<1000).map { try makeMessage(id: "msg_\($0)") }
        let outcome = try replaceAllSync(store, messages, owner: owner)

        XCTAssertEqual(outcome.insertedIds.count, 1000)
        XCTAssertEqual(store.count(matching: HightouchMessageQuery(), owner: owner), 1000)

        for boundary in [0, 199, 200, 399, 400, 999] {
            XCTAssertNotNil(store.message(withId: "msg_\(boundary)", owner: owner), "msg_\(boundary) should be present")
        }
    }

    // MARK: - Replace-from-server, scoped to owner

    func testReplaceFromServerDeletesOmittedRowsForOwnerAndLeavesOtherOwnersUntouched() throws {
        let store = try makeStore()
        let alice = MessageOwner(kind: .userId, id: "alice")
        let bob = MessageOwner(kind: .userId, id: "bob")

        try replaceAllSync(store, try [makeMessage(id: "a1"), makeMessage(id: "a2"), makeMessage(id: "a3")], owner: alice)
        try replaceAllSync(store, try [makeMessage(id: "b1")], owner: bob)

        let outcome = try replaceAllSync(store, [try makeMessage(id: "a1")], owner: alice)

        XCTAssertEqual(Set(outcome.removedIds), ["a2", "a3"])
        XCTAssertEqual(store.count(matching: HightouchMessageQuery(), owner: alice), 1)
        XCTAssertNotNil(store.message(withId: "a1", owner: alice))
        XCTAssertNil(store.message(withId: "a2", owner: alice))
        XCTAssertNil(store.message(withId: "a3", owner: alice))

        /// A fresh fetch passes even without `mergeChanges`. Only an object registered before the batch
        /// delete reveals the omission, so this retains one and asserts it flips to isDeleted.
        XCTAssertEqual(store.count(matching: HightouchMessageQuery(), owner: bob), 1)
        XCTAssertNotNil(store.message(withId: "b1", owner: bob))
    }

    // MARK: - Composite uniqueness constraint is real

    func testCompositeUniquenessConstraintCollapsesDuplicatePair() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")

        let expectation = expectation(description: "save duplicate pair")
        var saveError: Error?
        store.writeContext.perform {
            let now = Date()
            let first = Self.makeBareEntity(in: store.writeContext)
            first.messageId = "dup"
            first.ownerKey = owner.storageKey
            first.priorityRank = 1
            first.payload = Data([0x01])
            first.insertedAt = now

            let second = Self.makeBareEntity(in: store.writeContext)
            second.messageId = "dup"
            second.ownerKey = owner.storageKey
            second.priorityRank = 2
            second.payload = Data([0x02])
            second.insertedAt = now

            do {
                try store.writeContext.save()
            } catch {
                saveError = error
            }
            store.writeContext.reset()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        XCTAssertNil(saveError, "the trump merge policy should resolve the constraint violation, not throw")
        XCTAssertEqual(totalRowCount(store), 1, "two rows sharing (messageId, ownerKey) must collapse to one")
    }

    func testSameMessageIdIsAllowedForTwoDifferentOwners() throws {
        let store = try makeStore()
        let alice = MessageOwner(kind: .userId, id: "alice")
        let bob = MessageOwner(kind: .userId, id: "bob")

        try replaceAllSync(store, [try makeMessage(id: "shared", campaignId: "for_alice")], owner: alice)
        try replaceAllSync(store, [try makeMessage(id: "shared", campaignId: "for_bob")], owner: bob)

        XCTAssertEqual(totalRowCount(store), 2)
        XCTAssertEqual(try XCTUnwrap(store.message(withId: "shared", owner: alice)).campaignId, "for_alice")
        XCTAssertEqual(try XCTUnwrap(store.message(withId: "shared", owner: bob)).campaignId, "for_bob")
    }

    // MARK: - LRU cap

    func testEnforceLimitEvictsOldestByInsertedAtGloballyAcrossOwners() throws {
        let store = try makeStore()
        let alice = MessageOwner(kind: .userId, id: "alice")
        let bob = MessageOwner(kind: .userId, id: "bob")
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        let aOld = try makeMessage(id: "a_old")
        let aNew = try makeMessage(id: "a_new")
        let bOld = try makeMessage(id: "b_old")
        let bNew = try makeMessage(id: "b_new")

        /// A fresh fetch passes even without `mergeChanges`. Only an object registered before the batch
        /// delete reveals the omission, so this retains one and asserts it flips to isDeleted.
        try replaceAllSync(store, [aOld], owner: alice, now: base)
        try replaceAllSync(store, [bOld], owner: bob, now: base.addingTimeInterval(1))
        try replaceAllSync(store, [aOld, aNew], owner: alice, now: base.addingTimeInterval(2))
        try replaceAllSync(store, [bOld, bNew], owner: bob, now: base.addingTimeInterval(3))

        XCTAssertEqual(totalRowCount(store), 4)

        let evicted = enforceLimitSync(store, maxStoredMessages: 2)
        XCTAssertEqual(evicted, 2)
        XCTAssertEqual(totalRowCount(store), 2)

        XCTAssertNil(store.message(withId: "a_old", owner: alice), "oldest row overall should be evicted")
        XCTAssertNil(store.message(withId: "b_old", owner: bob), "second-oldest row overall should be evicted")
        XCTAssertNotNil(store.message(withId: "a_new", owner: alice))
        XCTAssertNotNil(store.message(withId: "b_new", owner: bob))
    }

    func testEnforceLimitIsNoOpWhenUnderTheCap() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        try replaceAllSync(store, [try makeMessage(id: "m1")], owner: owner)

        let evicted = enforceLimitSync(store, maxStoredMessages: 500)
        XCTAssertEqual(evicted, 0)
        XCTAssertEqual(totalRowCount(store), 1)
    }

    func testEnforceLimitPreservingAnOwnerEvictsOnlyOtherOwnersRows() throws {
        let store = try makeStore()
        let alice = MessageOwner(kind: .userId, id: "alice")
        let bob = MessageOwner(kind: .userId, id: "bob")
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        try replaceAllSync(store, [try makeMessage(id: "a1"), try makeMessage(id: "a2")], owner: alice, now: base)
        try replaceAllSync(store, [try makeMessage(id: "b1")], owner: bob, now: base.addingTimeInterval(1))

        let evicted = enforceLimitSync(store, maxStoredMessages: 2, preserving: alice)
        XCTAssertEqual(evicted, 1)
        XCTAssertNotNil(store.message(withId: "a1", owner: alice), "the preserved owner's rows are never evicted, even when oldest")
        XCTAssertNotNil(store.message(withId: "a2", owner: alice))
        XCTAssertNil(store.message(withId: "b1", owner: bob))
    }

    func testReplaceAllWithALimitKeepsTheHighestPriorityNewestMessages() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let oldDefault = try makeMessage(id: "old_default", createdAt: base)
        let newDefault = try makeMessage(id: "new_default", createdAt: base.addingTimeInterval(10))
        let oldHigh = try makeMessage(id: "old_high", priority: "high", createdAt: base)
        let undated = try makeMessage(id: "undated")

        let outcome = try replaceAllSync(store, [oldDefault, undated, newDefault, oldHigh], owner: owner, limit: 2)

        XCTAssertEqual(Set(outcome.insertedIds), ["old_high", "new_default"])
        XCTAssertEqual(totalRowCount(store), 2)
    }

    func testReplaceAllWithALimitReportsPreviouslyStoredRowsItDropsAsRemoved() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let older = try makeMessage(id: "older", createdAt: base)
        let newer = try makeMessage(id: "newer", createdAt: base.addingTimeInterval(10))
        try replaceAllSync(store, [older], owner: owner)

        let outcome = try replaceAllSync(store, [older, newer], owner: owner, limit: 1)

        XCTAssertEqual(outcome.insertedIds, ["newer"])
        XCTAssertEqual(outcome.removedIds, ["older"])

        let repeated = try replaceAllSync(store, [older, newer], owner: owner, limit: 1)
        XCTAssertTrue(repeated.insertedIds.isEmpty && repeated.removedIds.isEmpty, "a capped set must converge, not churn")
    }
}
#endif
