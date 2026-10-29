import Foundation
import XCTest
@testable import HightouchPush
import Hightouch

// Free functions rather than an `XCTestCase` extension, so a test class can still declare its own
// helper of the same name.

func makeMessage(
    id: String,
    campaignId: String? = nil,
    locationId: String? = nil,
    variantSlug: String? = nil,
    priority: String? = nil,
    createdAt: Date? = nil,
    expiresAt: Date? = nil
) throws -> HightouchMessage {
    var dict: [String: Any] = ["messageId": id]
    if let campaignId = campaignId { dict["campaignId"] = campaignId }
    if let locationId = locationId { dict["locationId"] = locationId }
    if let variantSlug = variantSlug { dict["variantSlug"] = variantSlug }
    if let priority = priority { dict["priority"] = priority }
    let formatter = ISO8601DateFormatter()
    if let createdAt = createdAt { dict["createdAt"] = formatter.string(from: createdAt) }
    if let expiresAt = expiresAt { dict["expiresAt"] = formatter.string(from: expiresAt) }
    return try HightouchMessage(raw: try JSON(dict))
}

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

func makeStore() throws -> MessageStore {
    try MessageStore(location: .ephemeral)
}

@discardableResult
func replaceAllSync(
    _ store: MessageStore,
    _ messages: [HightouchMessage],
    owner: MessageOwner,
    limit: Int? = nil,
    now: Date = Date()
) throws -> UpsertOutcome {
    let done = XCTestExpectation(description: "replaceAll")
    var outcome: Result<UpsertOutcome, Error>?
    store.replaceAll(messages, owner: owner, limit: limit, now: now) { result in
        outcome = result
        done.fulfill()
    }
    XCTWaiter().wait(for: [done], timeout: 5)
    return try XCTUnwrap(outcome).get()
}

/// Counts rows across every owner.
func totalRowCount(_ store: MessageStore) -> Int {
    var count = 0
    store.readContext.performAndWait {
        let fetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
        count = (try? store.readContext.count(for: fetch)) ?? 0
    }
    return count
}
#endif
