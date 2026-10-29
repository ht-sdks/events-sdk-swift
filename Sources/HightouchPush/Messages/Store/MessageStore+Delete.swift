import Foundation

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

extension MessageStore {
    /// `completion` receives the number of rows removed.
    func delete(messageId: String, owner: MessageOwner, completion: ((Int) -> Void)? = nil) {
        delete(messageIds: [messageId], owner: owner, completion: completion)
    }

    func delete(messageIds: [String], owner: MessageOwner, completion: ((Int) -> Void)? = nil) {
        guard !messageIds.isEmpty else {
            completion?(0)
            return
        }

        writeContext.perform {
            let predicate = NSPredicate(
                format: "%K == %@ AND %K IN %@",
                MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey,
                MessageStoreSchema.Attr.messageId.rawValue, messageIds
            )
            let deletedCount = (try? self.executeBatchDelete(matching: predicate).count) ?? 0
            self.writeContext.reset()
            completion?(deletedCount)
        }
    }

    func deleteAll(owner: MessageOwner, completion: (([String]) -> Void)? = nil) {
        let predicate = NSPredicate(format: "%K == %@", MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey)
        deleteReportingIds(matching: predicate, completion: completion)
    }

    /// Removes rows for every owner on the device. Debug tooling only.
    func deleteAllOwners(completion: (([String]) -> Void)? = nil) {
        deleteReportingIds(matching: nil, completion: completion)
    }

    /// Must run inside `writeContext.perform`. A batch delete bypasses every context, so
    /// `readContext` is told explicitly.
    func executeBatchDelete(matching predicate: NSPredicate?) throws -> [NSManagedObjectID] {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: MessageStoreSchema.entityName)
        fetch.predicate = predicate
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetch)
        deleteRequest.resultType = .resultTypeObjectIDs

        let result = try writeContext.execute(deleteRequest) as? NSBatchDeleteResult
        let objectIDs = result?.result as? [NSManagedObjectID] ?? []
        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
            into: [readContext]
        )
        return objectIDs
    }

    /// Reports the removed message ids, fetched first because a batch delete only returns object IDs.
    private func deleteReportingIds(matching predicate: NSPredicate?, completion: (([String]) -> Void)?) {
        writeContext.perform {
            do {
                let idFetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
                idFetch.predicate = predicate
                idFetch.returnsObjectsAsFaults = false
                let deletedIds = try self.writeContext.fetch(idFetch).map { $0.messageId }

                if !deletedIds.isEmpty {
                    _ = try self.executeBatchDelete(matching: predicate)
                }
                self.writeContext.reset()
                completion?(deletedIds)
            } catch {
                self.writeContext.reset()
                completion?([])
            }
        }
    }
}
#endif
