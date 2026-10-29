import Foundation

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

// `@objc(HTMessageEntity)` pins the runtime class name Core Data resolves against, so it doesn't
// change when the code is built under a different module name.
@objc(HTMessageEntity)
final class HTMessageEntity: NSManagedObject {
    @NSManaged var messageId: String
    @NSManaged var ownerKey: String
    @NSManaged var ownerUserId: String?
    @NSManaged var ownerAnonymousId: String?
    @NSManaged var messageType: String?
    @NSManaged var campaignId: String?
    @NSManaged var createdAt: Date?
    @NSManaged var expiresAt: Date?
    @NSManaged var priority: String?
    @NSManaged var priorityRank: Int32
    @NSManaged var locationId: String?
    @NSManaged var variantSlug: String?
    @NSManaged var triggerType: String?
    @NSManaged var messageVersion: String?
    @NSManaged var payload: Data
    @NSManaged var insertedAt: Date
    @NSManaged var updatedAt: Date
}
#endif
