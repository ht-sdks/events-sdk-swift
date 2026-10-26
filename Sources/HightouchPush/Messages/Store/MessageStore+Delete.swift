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
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: MessageStoreSchema.entityName)
            fetch.predicate = NSPredicate(
                format: "%K == %@ AND %K IN %@",
                MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey,
                MessageStoreSchema.Attr.messageId.rawValue, messageIds
            )

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetch)
            deleteRequest.resultType = .resultTypeObjectIDs

            do {
                let result = try self.writeContext.execute(deleteRequest) as? NSBatchDeleteResult
                let objectIDs = result?.result as? [NSManagedObjectID] ?? []

                // A batch delete bypasses every context, so `readContext` must be told explicitly.
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                    into: [self.readContext]
                )

                self.writeContext.reset()
                completion?(objectIDs.count)
            } catch {
                self.writeContext.reset()
                completion?(0)
            }
        }
    }

    /// Reports the removed message ids, fetched first because a batch delete only returns object IDs.
    func deleteAll(owner: MessageOwner, completion: (([String]) -> Void)? = nil) {
        writeContext.perform {
            let ownerPredicate = NSPredicate(
                format: "%K == %@",
                MessageStoreSchema.Attr.ownerKey.rawValue, owner.storageKey
            )

            do {
                let idFetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
                idFetch.predicate = ownerPredicate
                idFetch.returnsObjectsAsFaults = false
                let deletedIds = try self.writeContext.fetch(idFetch).map { $0.messageId }

                guard !deletedIds.isEmpty else {
                    self.writeContext.reset()
                    completion?([])
                    return
                }

                let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: MessageStoreSchema.entityName)
                fetch.predicate = ownerPredicate
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetch)
                deleteRequest.resultType = .resultTypeObjectIDs

                let result = try self.writeContext.execute(deleteRequest) as? NSBatchDeleteResult
                let objectIDs = result?.result as? [NSManagedObjectID] ?? []
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                    into: [self.readContext]
                )

                self.writeContext.reset()
                completion?(deletedIds)
            } catch {
                self.writeContext.reset()
                completion?([])
            }
        }
    }

    /// Removes rows for every owner on the device. Debug tooling only.
    func deleteAllOwners(completion: (([String]) -> Void)? = nil) {
        writeContext.perform {
            do {
                let idFetch = NSFetchRequest<HTMessageEntity>(entityName: MessageStoreSchema.entityName)
                idFetch.returnsObjectsAsFaults = false
                let deletedIds = try self.writeContext.fetch(idFetch).map { $0.messageId }

                guard !deletedIds.isEmpty else {
                    self.writeContext.reset()
                    completion?([])
                    return
                }

                let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: MessageStoreSchema.entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetch)
                deleteRequest.resultType = .resultTypeObjectIDs

                let result = try self.writeContext.execute(deleteRequest) as? NSBatchDeleteResult
                let objectIDs = result?.result as? [NSManagedObjectID] ?? []
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                    into: [self.readContext]
                )

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
