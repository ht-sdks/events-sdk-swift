import Foundation

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

extension MessageStore {
    /// Reclaims disk space used by expired rows. Space only: reads already hide expired rows via
    /// the query-time predicate, whose `<=` boundary this matches.
    func pruneExpired(asOf now: Date = Date(), completion: ((Int) -> Void)? = nil) {
        writeContext.perform {
            let predicate = NSPredicate(
                format: "%K != nil AND %K <= %@",
                MessageStoreSchema.Attr.expiresAt.rawValue,
                MessageStoreSchema.Attr.expiresAt.rawValue,
                now as NSDate
            )
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: MessageStoreSchema.entityName)
            fetch.predicate = predicate

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
}
#endif
