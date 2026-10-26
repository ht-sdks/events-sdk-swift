import Foundation

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

extension MessageStore {
    /// Decodes from `payload`, the full message; the typed columns exist only for filtering and sorting.
    func messages(matching query: HightouchMessageQuery, owner: MessageOwner) -> [HightouchMessage] {
        var result: [HightouchMessage] = []
        readContext.performAndWait {
            let fetch = MessageStore.fetchRequest(matching: query, owner: owner)
            guard let entities = try? self.readContext.fetch(fetch) else { return }
            result = entities.compactMap { try? HightouchMessage.decode(payload: $0.payload) }
        }
        return result
    }

    func message(withId messageId: String, owner: MessageOwner) -> HightouchMessage? {
        var result: HightouchMessage?
        readContext.performAndWait {
            let fetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
            fetch.predicate = NSPredicate(
                format: "%K == %@ AND %K == %@",
                MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey,
                MessageStoreSchema.Attr.messageId.rawValue, messageId
            )
            fetch.fetchLimit = 1
            fetch.returnsObjectsAsFaults = false
            guard let entity = (try? self.readContext.fetch(fetch))?.first else { return }
            result = try? HightouchMessage.decode(payload: entity.payload)
        }
        return result
    }

    func count(matching query: HightouchMessageQuery, owner: MessageOwner) -> Int {
        var result = 0
        readContext.performAndWait {
            let fetch = MessageStore.fetchRequest(matching: query, owner: owner)
            result = (try? self.readContext.count(for: fetch)) ?? 0
        }
        return result
    }

    /// The owner predicate is unconditional: it is what keeps one user from reading another's rows.
    private static func fetchRequest(matching query: HightouchMessageQuery, owner: MessageOwner) -> NSFetchRequest<HTMessageEntity> {
        let fetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)

        var predicates: [NSPredicate] = [
            NSPredicate(format: "%K == %@", MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey)
        ]

        if let locationId = query.locationId {
            predicates.append(NSPredicate(format: "%K == %@", MessageStoreSchema.Attr.locationId.rawValue, locationId))
        }
        if let variantSlug = query.variantSlug {
            predicates.append(NSPredicate(format: "%K == %@", MessageStoreSchema.Attr.variantSlug.rawValue, variantSlug))
        }
        if !query.includeExpired {
            let now = query.now ?? Date()
            predicates.append(NSPredicate(
                format: "%K == nil OR %K > %@",
                MessageStoreSchema.Attr.expiresAt.rawValue,
                MessageStoreSchema.Attr.expiresAt.rawValue,
                now as NSDate
            ))
        }

        fetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        fetch.sortDescriptors = MessageStore.sortDescriptors(for: query.sort)
        fetch.returnsObjectsAsFaults = false
        fetch.shouldRefreshRefetchedObjects = true

        if let limit = query.limit, limit > 0 {
            fetch.fetchLimit = limit
        }

        return fetch
    }

    /// `messageId` is the final tiebreaker so the order is stable across calls.
    private static func sortDescriptors(for sort: HightouchMessageSort) -> [NSSortDescriptor] {
        let priorityRank = MessageStoreSchema.Attr.priorityRank.rawValue
        let createdAt = MessageStoreSchema.Attr.createdAt.rawValue
        let messageId = MessageStoreSchema.Attr.messageId.rawValue

        switch sort {
        case .priorityThenNewest:
            return [
                NSSortDescriptor(key: priorityRank, ascending: true),
                NSSortDescriptor(key: createdAt, ascending: false),
                NSSortDescriptor(key: messageId, ascending: true)
            ]
        case .priorityThenOldest:
            return [
                NSSortDescriptor(key: priorityRank, ascending: true),
                NSSortDescriptor(key: createdAt, ascending: true),
                NSSortDescriptor(key: messageId, ascending: true)
            ]
        case .newestFirst:
            return [
                NSSortDescriptor(key: createdAt, ascending: false),
                NSSortDescriptor(key: messageId, ascending: true)
            ]
        case .oldestFirst:
            return [
                NSSortDescriptor(key: createdAt, ascending: true),
                NSSortDescriptor(key: messageId, ascending: true)
            ]
        }
    }
}
#endif
