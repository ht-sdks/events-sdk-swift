import XCTest
@testable import HightouchPush
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

/// Installed per session via `protocolClasses`: a session with explicit protocol classes ignores
/// globally registered ones, so this intercepts only this client's traffic.
final class MessageStore_Delete_Tests: XCTestCase {

    private func makeStore() throws -> MessageStore {
        try MessageStore(location: .ephemeral)
    }

    private func makeMessage(id: String) throws -> HightouchMessage {
        try HightouchMessage(raw: try JSON(["messageId": id]))
    }

    @discardableResult
    private func replaceAllSync(
        _ store: MessageStore,
        _ messages: [HightouchMessage],
        owner: MessageOwner
    ) throws -> UpsertOutcome {
        let done = expectation(description: "replaceAll")
        var outcome: Result<UpsertOutcome, Error>?
        store.replaceAll(messages, owner: owner) { result in
            outcome = result
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return try XCTUnwrap(outcome).get()
    }

    @discardableResult
    private func deleteSync(_ store: MessageStore, messageId: String, owner: MessageOwner) -> Int {
        let done = expectation(description: "delete")
        var removed = -1
        store.delete(messageId: messageId, owner: owner) { count in
            removed = count
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return removed
    }

    private func ids(_ store: MessageStore, owner: MessageOwner) -> [String] {
        store.messages(matching: HightouchMessageQuery(), owner: owner).map(\.messageId).sorted()
    }

    func testDeleteRemovesOnlyTheNamedMessage() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        try replaceAllSync(store, [
            try makeMessage(id: "m1"),
            try makeMessage(id: "m2"),
            try makeMessage(id: "m3"),
        ], owner: owner)

        XCTAssertEqual(deleteSync(store, messageId: "m2", owner: owner), 1)
        XCTAssertEqual(ids(store, owner: owner), ["m1", "m3"])
    }

    /// URLSession moves `httpBody` into `httpBodyStream` before a URLProtocol sees the request.
    func testDeleteIsScopedToOwner() throws {
        let store = try makeStore()
        let alice = MessageOwner(kind: .userId, id: "alice")
        let anon = MessageOwner(kind: .anonymousId, id: "anon-1")
        try replaceAllSync(store, [try makeMessage(id: "shared")], owner: alice)
        try replaceAllSync(store, [try makeMessage(id: "shared")], owner: anon)

        XCTAssertEqual(deleteSync(store, messageId: "shared", owner: alice), 1)

        XCTAssertEqual(ids(store, owner: alice), [])
        XCTAssertEqual(ids(store, owner: anon), ["shared"], "another owner's identically-named row must survive")
    }

    /// Once the queue is empty, the last response repeats.
    func testDeletingUnknownMessageRemovesNothingAndDoesNotThrow() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        try replaceAllSync(store, [try makeMessage(id: "m1")], owner: owner)

        XCTAssertEqual(deleteSync(store, messageId: "nope", owner: owner), 0)
        XCTAssertEqual(ids(store, owner: owner), ["m1"])
    }

    /// Locked: `reportInternalError` can call the error handler from a background queue.
    func testDeleteMarksAlreadyRegisteredObjectAsDeleted() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        try replaceAllSync(store, [try makeMessage(id: "m1"), try makeMessage(id: "m2")], owner: owner)

        var retained: HTMessageEntity!
        store.readContext.performAndWait {
            let fetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
            fetch.predicate = NSPredicate(
                format: "%K == %@ AND %K == %@",
                MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey,
                MessageStoreSchema.Attr.messageId.rawValue, "m1"
            )
            fetch.returnsObjectsAsFaults = false
            retained = try? store.readContext.fetch(fetch).first
        }
        XCTAssertNotNil(retained, "precondition: the row must be registered in readContext before the delete")

        XCTAssertEqual(deleteSync(store, messageId: "m1", owner: owner), 1)

        store.readContext.performAndWait {
            XCTAssertTrue(
                retained.isDeleted,
                "a row readContext already had registered before the delete must be marked deleted afterwards"
            )
        }

        XCTAssertEqual(ids(store, owner: owner), ["m2"])
        XCTAssertNil(store.message(withId: "m1", owner: owner))
    }
}
#endif
