import Foundation

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

/// What changed as the result of one `replaceAll(...)` call.
struct UpsertOutcome {
    let insertedIds: [String]
    let updatedIds: [String]
    let removedIds: [String]
    let unchanged: Int
}

extension MessageStore {
    /// Keeps each `IN` clause under SQLite's bound-variable limit (as low as 999 on older builds).
    private static let upsertChunkSize = 200

    /// Applies a fetched server set for `owner` in one write: replaces `owner`'s rows (capped at
    /// `maxStoredMessages`), prunes expired rows, then evicts other owners' oldest rows until the
    /// store is under the cap. The outcome is every change to `owner`'s rows; messages already
    /// expired at `now` are dropped first, so their rows show up in `removedIds`.
    /// `completion` runs on the write queue.
    func reconcile(
        _ messages: [HightouchMessage],
        owner: MessageOwner,
        maxStoredMessages: Int,
        now: Date = Date(),
        suppressing suppressedIds: @escaping () -> Set<String> = { [] },
        completion: ((Result<UpsertOutcome, Error>) -> Void)?
    ) {
        writeContext.perform {
            do {
                let unexpired = messages.filter { $0.expiresAt.map { $0 > now } ?? true }
                let outcome = try self.replaceAllInWriteContext(
                    unexpired, owner: owner, limit: maxStoredMessages, now: now, suppressed: suppressedIds()
                )
                _ = try self.executeBatchDelete(matching: MessageStore.expiredPredicate(asOf: now))
                self.writeContext.reset()
                // `owner` already fits under the cap, so only other owners' rows are evicted.
                _ = try self.enforceLimitInWriteContext(maxStoredMessages: maxStoredMessages, preserving: owner)
                completion?(.success(outcome))
            } catch {
                self.writeContext.reset()
                completion?(.failure(error))
            }
        }
    }

    /// Replaces everything stored for `owner` with `messages`: rows not repeated are deleted.
    /// `limit` keeps only the first messages in `.priorityThenNewest` order, so an owner whose server
    /// set exceeds the store cap converges instead of being evicted and re-inserted every sync.
    /// `completion` runs on the write queue.
    func replaceAll(
        _ messages: [HightouchMessage],
        owner: MessageOwner,
        limit: Int? = nil,
        now: Date = Date(),
        suppressing suppressedIds: @escaping () -> Set<String> = { [] },
        completion: ((Result<UpsertOutcome, Error>) -> Void)?
    ) {
        writeContext.perform {
            completion?(Result {
                try self.replaceAllInWriteContext(messages, owner: owner, limit: limit, now: now, suppressed: suppressedIds())
            })
        }
    }

    /// Evicts the oldest rows until at most `maxStoredMessages` remain. Rows owned by `preserving`
    /// are never evicted, so a sync never removes the current owner's rows without reporting them.
    func enforceLimit(maxStoredMessages: Int, preserving owner: MessageOwner? = nil, completion: ((Int) -> Void)? = nil) {
        writeContext.perform {
            let evicted = (try? self.enforceLimitInWriteContext(maxStoredMessages: maxStoredMessages, preserving: owner)) ?? 0
            completion?(evicted)
        }
    }

    /// Must run inside `writeContext.perform`. `suppressed` must be read there too: a dismissal
    /// records an id before enqueueing its delete, so any id recorded after the read is deleted
    /// after this write.
    private func replaceAllInWriteContext(
        _ messages: [HightouchMessage],
        owner: MessageOwner,
        limit: Int?,
        now: Date,
        suppressed: Set<String>
    ) throws -> UpsertOutcome {
        defer { writeContext.reset() }

        let candidates = suppressed.isEmpty
            ? messages
            : messages.filter { !suppressed.contains($0.messageId) }
        // A response may repeat an id; last one wins.
        var deduped: [String: HightouchMessage] = [:]
        var order: [String] = []
        for message in candidates {
            if deduped[message.messageId] == nil {
                order.append(message.messageId)
            }
            deduped[message.messageId] = message
        }
        var unique = order.map { deduped[$0]! }
        if let limit = limit, unique.count > limit {
            unique = Array(unique.sorted(by: MessageStore.priorityThenNewest).prefix(max(limit, 0)))
        }

        var insertedIds: [String] = []
        var updatedIds: [String] = []
        var unchangedCount = 0

        for chunk in unique.htChunked(into: MessageStore.upsertChunkSize) {
            let chunkIds = chunk.map { $0.messageId }

            let fetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
            fetch.predicate = NSPredicate(
                format: "%K == %@ AND %K IN %@",
                MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey,
                MessageStoreSchema.Attr.messageId.rawValue, chunkIds
            )
            fetch.returnsObjectsAsFaults = false

            var existingById: [String: HTMessageEntity] = [:]
            for entity in try writeContext.fetch(fetch) {
                existingById[entity.messageId] = entity
            }

            for message in chunk {
                let newPayload = try message.payloadData()

                if let entity = existingById[message.messageId] {
                    // Rows written by an older encoding can differ in bytes alone, so
                    // fall back to a structural compare.
                    let unchanged: Bool
                    if entity.payload == newPayload {
                        unchanged = true
                    } else if let storedMessage = try? HightouchMessage.decode(payload: entity.payload) {
                        unchanged = storedMessage == message
                    } else {
                        unchanged = false
                    }
                    if unchanged {
                        unchangedCount += 1
                        continue
                    }
                    MessageStore.apply(message, payload: newPayload, to: entity, owner: owner, now: now, isNew: false)
                    updatedIds.append(message.messageId)
                } else {
                    let entity = MessageStore.makeEntity(in: writeContext)
                    MessageStore.apply(message, payload: newPayload, to: entity, owner: owner, now: now, isNew: true)
                    insertedIds.append(message.messageId)
                }
            }
        }

        let keepFetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
        keepFetch.predicate = NSPredicate(
            format: "%K == %@", MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey
        )
        keepFetch.returnsObjectsAsFaults = false
        let allForOwner = try writeContext.fetch(keepFetch)

        let keepIds = Set(unique.map { $0.messageId })
        var removedIds: [String] = []
        for entity in allForOwner where !keepIds.contains(entity.messageId) {
            removedIds.append(entity.messageId)
            writeContext.delete(entity)
        }

        // The uniqueness constraint is only a backstop; the trump merge policy keeps a
        // collision from failing the save.
        if writeContext.hasChanges {
            try writeContext.save()
        }
        return UpsertOutcome(
            insertedIds: insertedIds,
            updatedIds: updatedIds,
            removedIds: removedIds,
            unchanged: unchangedCount
        )
    }

    /// Must run inside `writeContext.perform`.
    private func enforceLimitInWriteContext(maxStoredMessages: Int, preserving owner: MessageOwner?) throws -> Int {
        defer { writeContext.reset() }
        guard maxStoredMessages >= 0 else { return 0 }

        let countFetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
        let overage = try writeContext.count(for: countFetch) - maxStoredMessages
        guard overage > 0 else { return 0 }

        let fetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
        if let owner = owner {
            fetch.predicate = NSPredicate(
                format: "%K != %@", MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey
            )
        }
        fetch.sortDescriptors = [NSSortDescriptor(key: MessageStoreSchema.Attr.insertedAt.rawValue, ascending: true)]
        fetch.fetchLimit = overage
        fetch.returnsObjectsAsFaults = false

        let oldest = try writeContext.fetch(fetch)
        for entity in oldest {
            writeContext.delete(entity)
        }
        if writeContext.hasChanges {
            try writeContext.save()
        }
        return oldest.count
    }

    /// Mirrors `HightouchMessageSort.priorityThenNewest`; messages without `createdAt` sort last,
    /// as nil does in a descending Core Data sort.
    private static func priorityThenNewest(_ lhs: HightouchMessage, _ rhs: HightouchMessage) -> Bool {
        if lhs.priorityRank != rhs.priorityRank { return lhs.priorityRank < rhs.priorityRank }
        switch (lhs.createdAt, rhs.createdAt) {
        case let (l?, r?) where l != r: return l > r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.messageId < rhs.messageId
        }
    }

    /// Not `HTMessageEntity(context:)`, whose class-based entity lookup is ambiguous if more than
    /// one model describing the class exists; this resolves through the context's coordinator.
    private static func makeEntity(in context: NSManagedObjectContext) -> HTMessageEntity {
        NSEntityDescription.insertNewObject(forEntityName: MessageStoreSchema.entityName, into: context) as! HTMessageEntity
    }

    private static func apply(
        _ message: HightouchMessage,
        payload: Data,
        to entity: HTMessageEntity,
        owner: MessageOwner,
        now: Date,
        isNew: Bool
    ) {
        entity.messageId = message.messageId
        entity.ownerKey = owner.storageKey
        entity.messageType = message.messageType
        entity.campaignId = message.campaignId
        entity.createdAt = message.createdAt
        entity.expiresAt = message.expiresAt
        entity.priorityRank = message.priorityRank
        entity.locationId = message.locationId
        entity.variantSlug = message.variantSlug
        entity.messageVersion = message.version
        entity.payload = payload
        if isNew {
            entity.insertedAt = now
        }
    }
}

private extension Array {
    func htChunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
#endif
