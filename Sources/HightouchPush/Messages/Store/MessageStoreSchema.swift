import Foundation

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

/// The Core Data model, built in code: `momc` is Xcode-only, so an `.xcdatamodeld` would break
/// `swift build`. `payload` holds the full message JSON; every other attribute is a projection of
/// it for filtering and sorting.
enum MessageStoreSchema {
    /// Part of the store filename, so bumping it starts a fresh store.
    static let modelVersion = 2

    static let entityName = "HTMessageEntity"

    enum Attr: String {
        case messageId
        case ownerKey
        case messageType
        case campaignId
        case createdAt
        case expiresAt
        case priority
        case priorityRank
        case locationId
        case variantSlug
        case triggerType
        /// Not `version`, which collides with `NSObject.version`.
        case messageVersion
        case payload
        case insertedAt
        case updatedAt
    }

    /// One model per process: two live models claiming the same class make Core Data's
    /// class-to-entity lookup ambiguous, which has been seen to read rows with the wrong model.
    static func makeModel() -> NSManagedObjectModel {
        sharedModel
    }

    private static let sharedModel: NSManagedObjectModel = buildModel()

    private static func buildModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = entityName
        entity.managedObjectClassName = NSStringFromClass(HTMessageEntity.self)

        func attribute(
            _ attr: Attr,
            type: NSAttributeType,
            optional: Bool,
            defaultValue: Any? = nil
        ) -> NSAttributeDescription {
            let description = NSAttributeDescription()
            description.name = attr.rawValue
            description.attributeType = type
            description.isOptional = optional
            if let defaultValue = defaultValue {
                description.defaultValue = defaultValue
            }
            return description
        }

        let messageId = attribute(.messageId, type: .stringAttributeType, optional: false)
        let ownerKey = attribute(.ownerKey, type: .stringAttributeType, optional: false)
        let messageType = attribute(.messageType, type: .stringAttributeType, optional: true)
        let campaignId = attribute(.campaignId, type: .stringAttributeType, optional: true)
        let createdAt = attribute(.createdAt, type: .dateAttributeType, optional: true)
        // nil means "never expires".
        let expiresAt = attribute(.expiresAt, type: .dateAttributeType, optional: true)
        let priority = attribute(.priority, type: .stringAttributeType, optional: true)
        let priorityRank = attribute(
            .priorityRank, type: .integer32AttributeType, optional: false, defaultValue: Int32.max
        )
        let locationId = attribute(.locationId, type: .stringAttributeType, optional: true)
        let variantSlug = attribute(.variantSlug, type: .stringAttributeType, optional: true)
        let triggerType = attribute(.triggerType, type: .stringAttributeType, optional: true)
        let messageVersion = attribute(.messageVersion, type: .stringAttributeType, optional: true)
        let payload = attribute(.payload, type: .binaryDataAttributeType, optional: false)
        payload.allowsExternalBinaryDataStorage = true
        let insertedAt = attribute(.insertedAt, type: .dateAttributeType, optional: false)
        let updatedAt = attribute(.updatedAt, type: .dateAttributeType, optional: false)

        entity.properties = [
            messageId, ownerKey, messageType, campaignId,
            createdAt, expiresAt, priority, priorityRank, locationId, variantSlug, triggerType,
            messageVersion, payload, insertedAt, updatedAt
        ]

        // Composite: the same message id can be cached for two owners on one device.
        entity.uniquenessConstraints = [[Attr.messageId.rawValue, Attr.ownerKey.rawValue]]

        func index(_ name: String, _ attributes: [NSAttributeDescription]) -> NSFetchIndexDescription {
            NSFetchIndexDescription(
                name: name,
                elements: attributes.map { NSFetchIndexElementDescription(property: $0, collationType: .binary) }
            )
        }

        entity.indexes = [
            index("idx_owner_message", [ownerKey, messageId]),
            index("idx_owner_location_variant", [ownerKey, locationId, variantSlug]),
            index("idx_owner_variant", [ownerKey, variantSlug]),
            index("idx_owner_expires", [ownerKey, expiresAt]),
            // For the cross-owner prune.
            index("idx_expires", [expiresAt]),
            index("idx_owner_sort", [ownerKey, priorityRank, createdAt])
        ]

        model.entities = [entity]
        return model
    }
}
#endif
