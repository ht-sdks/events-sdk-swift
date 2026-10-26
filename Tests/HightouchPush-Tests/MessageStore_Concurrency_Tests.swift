import XCTest
@testable import HightouchPush
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class MessageStore_Concurrency_Tests: XCTestCase {

    private func makeStore() throws -> MessageStore {
        try MessageStore(writeKey: "\(name)-\(UUID().uuidString)", location: .ephemeral)
    }

    private func makeMessage(id: String) throws -> HightouchMessage {
        try HightouchMessage(raw: try JSON(["messageId": id]))
    }

    private func totalRowCount(_ store: MessageStore) -> Int {
        var count = 0
        store.readContext.performAndWait {
            let fetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
            count = (try? store.readContext.count(for: fetch)) ?? 0
        }
        return count
    }

    private func assertEventuallyDeallocated(_ instance: AnyObject, file: StaticString = #filePath, line: UInt = #line) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(instance, "instance should have been deallocated; potential leak", file: file, line: line)
        }
    }

    // MARK: - Concurrent replaceAll, overlapping ids, no crash

    func test8ConcurrentReplaceAllAcrossOwnersWithOverlappingIdsUnionWithNoCrash() throws {
        let store = try makeStore()
        let owners = (0..<8).map { MessageOwner(kind: .userId, id: "owner_\($0)") }
        let sharedIds = (0..<20).map { "shared_\($0)" }

        let completion = expectation(description: "all 8 replaceAll calls complete")
        completion.expectedFulfillmentCount = 8

        DispatchQueue.concurrentPerform(iterations: owners.count) { index in
            do {
                let ids = sharedIds + ["unique_\(index)"]
                let messages = try ids.map { try self.makeMessage(id: $0) }
                store.replaceAll(messages, owner: owners[index], now: Date()) { result in
                    if case .failure(let error) = result {
                        XCTFail("replaceAll failed for owner \(index): \(error)")
                    }
                    completion.fulfill()
                }
            } catch {
                XCTFail("fixture construction failed: \(error)")
                completion.fulfill()
            }
        }
        wait(for: [completion], timeout: 15)

        let expectedPerOwner = sharedIds.count + 1
        XCTAssertEqual(totalRowCount(store), owners.count * expectedPerOwner)
        for (index, owner) in owners.enumerated() {
            XCTAssertEqual(store.count(matching: HightouchMessageQuery(), owner: owner), expectedPerOwner)
            XCTAssertNotNil(store.message(withId: "unique_\(index)", owner: owner))
        }
    }

    // MARK: - Read during a large in-flight write

    func testReadDuringLargeInFlightWriteReturnsAConsistentSnapshot() throws {
        let store = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")
        let messages = try (0..<2000).map { try makeMessage(id: "m\($0)") }

        let writeCompletion = expectation(description: "large write completes")
        store.replaceAll(messages, owner: owner, now: Date()) { result in
            if case .failure(let error) = result {
                XCTFail("replaceAll failed: \(error)")
            }
            writeCompletion.fulfill()
        }

        for _ in 0..<20 {
            let count = store.count(matching: HightouchMessageQuery(), owner: owner)
            XCTAssertTrue((0...2000).contains(count), "expected a consistent snapshot, got \(count)")
        }

        wait(for: [writeCompletion], timeout: 15)
        XCTAssertEqual(store.count(matching: HightouchMessageQuery(), owner: owner), 2000)
    }

    // MARK: - No leaks

    func testStoreIsDeallocatedOnceNothingRetainsIt() throws {
        var store: MessageStore? = try makeStore()
        let owner = MessageOwner(kind: .userId, id: "alice")

        let completion = expectation(description: "replaceAll completes")
        store?.replaceAll([try makeMessage(id: "m1")], owner: owner, now: Date()) { _ in completion.fulfill() }
        wait(for: [completion], timeout: 5)

        assertEventuallyDeallocated(store!)
        store = nil
    }
}
#endif
