import XCTest
@testable import HightouchPush
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class MessageStore_Query_Tests: XCTestCase {

    private func makeStore() throws -> MessageStore {
        try MessageStore(writeKey: "\(name)-\(UUID().uuidString)", location: .ephemeral)
    }

    private func makeMessage(
        id: String,
        locationId: String? = nil,
        variantSlug: String? = nil,
        priority: String? = nil,
        createdAt: Date? = nil
    ) throws -> HightouchMessage {
        var dict: [String: Any] = ["messageId": id]
        if let locationId = locationId { dict["locationId"] = locationId }
        if let variantSlug = variantSlug { dict["variantSlug"] = variantSlug }
        if let priority = priority { dict["priority"] = priority }
        if let createdAt = createdAt { dict["createdAt"] = ISO8601DateFormatter().string(from: createdAt) }
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

    // MARK: - Filter combinations

    func testLocationOnlyVariantOnlyBothAndNeitherFilters() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")

        try replaceAllSync(store, try [
            makeMessage(id: "m_loc_a_var_x", locationId: "loc_a", variantSlug: "var_x"),
            makeMessage(id: "m_loc_a_var_y", locationId: "loc_a", variantSlug: "var_y"),
            makeMessage(id: "m_loc_b_var_x", locationId: "loc_b", variantSlug: "var_x"),
            makeMessage(id: "m_no_location", variantSlug: "var_x")
        ], owner: owner)

        let neither = store.messages(matching: HightouchMessageQuery(), owner: owner)
        XCTAssertEqual(neither.count, 4)

        let locationOnly = store.messages(matching: HightouchMessageQuery(locationId: "loc_a"), owner: owner)
        XCTAssertEqual(Set(locationOnly.map { $0.messageId }), ["m_loc_a_var_x", "m_loc_a_var_y"])

        let variantOnly = store.messages(matching: HightouchMessageQuery(variantSlug: "var_x"), owner: owner)
        XCTAssertEqual(Set(variantOnly.map { $0.messageId }), ["m_loc_a_var_x", "m_loc_b_var_x", "m_no_location"])

        let both = store.messages(matching: HightouchMessageQuery(locationId: "loc_a", variantSlug: "var_x"), owner: owner)
        XCTAssertEqual(both.map { $0.messageId }, ["m_loc_a_var_x"])
    }

    // MARK: - Owner scoping

    func testRowsForAnotherOwnerAreNeverReturnedByAnyQuery() throws {
        let store = try makeStore()
        let alice = MessageOwner(kind: .userId, id: "alice")
        let bob = MessageOwner(kind: .userId, id: "bob")

        try replaceAllSync(store, [try makeMessage(id: "alice_msg")], owner: alice)
        try replaceAllSync(store, [try makeMessage(id: "bob_msg")], owner: bob)

        XCTAssertEqual(store.messages(matching: HightouchMessageQuery(), owner: bob).map { $0.messageId }, ["bob_msg"])
        XCTAssertEqual(store.count(matching: HightouchMessageQuery(), owner: bob), 1)
        XCTAssertNil(store.message(withId: "alice_msg", owner: bob))
        XCTAssertNotNil(store.message(withId: "alice_msg", owner: alice))

        let everythingBobCanSee = store.messages(matching: HightouchMessageQuery(includeExpired: true), owner: bob)
        XCTAssertFalse(everythingBobCanSee.contains { $0.messageId == "alice_msg" })
    }

    // MARK: - Limit

    func testLimitHonoredZeroAndNegativeAreUnlimited() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        try replaceAllSync(store, try (0..<5).map { try makeMessage(id: "m\($0)") }, owner: owner)

        XCTAssertEqual(store.messages(matching: HightouchMessageQuery(limit: 2), owner: owner).count, 2)
        XCTAssertEqual(store.messages(matching: HightouchMessageQuery(limit: 0), owner: owner).count, 5)
        XCTAssertEqual(store.messages(matching: HightouchMessageQuery(limit: -1), owner: owner).count, 5)
        XCTAssertEqual(store.messages(matching: HightouchMessageQuery(limit: nil), owner: owner).count, 5)
    }

    // MARK: - Ordering: exact sequence for mixed rank + date

    func testExactIdSequenceForMixedPriorityRankAndCreatedAt() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        try replaceAllSync(store, try [
            makeMessage(id: "low_old", priority: "300", createdAt: base),
            makeMessage(id: "low_new", priority: "300", createdAt: base.addingTimeInterval(100)),
            makeMessage(id: "high_old", priority: "0", createdAt: base),
            makeMessage(id: "high_new", priority: "0", createdAt: base.addingTimeInterval(100))
        ], owner: owner)

        let ordered = store.messages(matching: HightouchMessageQuery(sort: .priorityThenNewest), owner: owner)
        XCTAssertEqual(ordered.map { $0.messageId }, ["high_new", "high_old", "low_new", "low_old"])

        let oldestFirst = store.messages(matching: HightouchMessageQuery(sort: .priorityThenOldest), owner: owner)
        XCTAssertEqual(oldestFirst.map { $0.messageId }, ["high_old", "high_new", "low_old", "low_new"])

        let newest = store.messages(matching: HightouchMessageQuery(sort: .newestFirst), owner: owner)
        XCTAssertEqual(newest.map { $0.messageId }, ["high_new", "low_new", "high_old", "low_old"])

        let oldest = store.messages(matching: HightouchMessageQuery(sort: .oldestFirst), owner: owner)
        XCTAssertEqual(oldest.map { $0.messageId }, ["high_old", "low_old", "high_new", "low_new"])
    }

    // MARK: - Total-order stability

    func testTotalOrderIsStableAcross20RepeatedFetchesForIdenticalRankAndDate() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let sameInstant = Date(timeIntervalSince1970: 1_700_000_000)

        // The provider runs on the coordinator's queue, so key the switch to call order, not the test's timeline.
        let messages = try (0..<10).map { try makeMessage(id: "m\($0)", priority: "100", createdAt: sameInstant) }
        try replaceAllSync(store, messages, owner: owner)

        let expectedOrder = (0..<10).map { "m\($0)" }.sorted()
        for _ in 0..<20 {
            let ids = store.messages(matching: HightouchMessageQuery(), owner: owner).map { $0.messageId }
            XCTAssertEqual(ids, expectedOrder)
        }
    }

    // MARK: - Predicate-injection safety

    func testLocationIdContainingQuoteAndPercentMatchesCorrectly() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let trickyLocationId = "home's 100% banner"

        try replaceAllSync(store, try [
            makeMessage(id: "tricky", locationId: trickyLocationId),
            makeMessage(id: "other", locationId: "home_banner")
        ], owner: owner)

        let matched = store.messages(matching: HightouchMessageQuery(locationId: trickyLocationId), owner: owner)
        XCTAssertEqual(matched.map { $0.messageId }, ["tricky"])

        let unmatched = store.messages(matching: HightouchMessageQuery(locationId: "home_banner"), owner: owner)
        XCTAssertEqual(unmatched.map { $0.messageId }, ["other"])
    }

    // MARK: - message(withId:) and count(matching:)

    func testMessageWithIdReturnsNilWhenAbsent() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        XCTAssertNil(store.message(withId: "nope", owner: owner))
    }

    func testCountMatchesFilteredMessagesCount() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        try replaceAllSync(store, try [
            makeMessage(id: "a", locationId: "loc_a"),
            makeMessage(id: "b", locationId: "loc_a"),
            makeMessage(id: "c", locationId: "loc_b")
        ], owner: owner)

        XCTAssertEqual(store.count(matching: HightouchMessageQuery(locationId: "loc_a"), owner: owner), 2)
        XCTAssertEqual(store.count(matching: HightouchMessageQuery(), owner: owner), 3)
    }
}
#endif
