import Foundation

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

extension MessageStore {
    /// Reclaims disk space used by expired rows. Space only: reads already hide expired rows via
    /// the query-time predicate, whose `<=` boundary this matches.
    func pruneExpired(asOf now: Date = Date(), completion: ((Int) -> Void)? = nil) {
        writeContext.perform {
            let prunedCount = (try? self.executeBatchDelete(matching: MessageStore.expiredPredicate(asOf: now)).count) ?? 0
            self.writeContext.reset()
            completion?(prunedCount)
        }
    }

    static func expiredPredicate(asOf now: Date) -> NSPredicate {
        NSPredicate(
            format: "%K != nil AND %K <= %@",
            MessageStoreSchema.Attr.expiresAt.rawValue,
            MessageStoreSchema.Attr.expiresAt.rawValue,
            now as NSDate
        )
    }
}
#endif
