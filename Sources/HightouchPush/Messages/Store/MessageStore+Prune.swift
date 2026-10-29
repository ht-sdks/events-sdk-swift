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
            let prunedCount = (try? self.executeBatchDelete(matching: predicate).count) ?? 0
            self.writeContext.reset()
            completion?(prunedCount)
        }
    }
}
#endif
