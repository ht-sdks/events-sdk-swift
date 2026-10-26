import XCTest
@testable import HightouchPush

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class MessageStoreSchema_Tests: XCTestCase {
    private let model = MessageStoreSchema.makeModel()
    private var entity: NSEntityDescription {
        model.entitiesByName[MessageStoreSchema.entityName]!
    }

    // MARK: - Attributes: name / type / optionality / default

    func testAttributeTableMatchesExpectedShape() {
        struct Expected {
            let type: NSAttributeType
            let optional: Bool
            let defaultValue: AnyHashable?
        }

        let expected: [MessageStoreSchema.Attr: Expected] = [
            .messageId: Expected(type: .stringAttributeType, optional: false, defaultValue: nil),
            .ownerKey: Expected(type: .stringAttributeType, optional: false, defaultValue: nil),
            .ownerUserId: Expected(type: .stringAttributeType, optional: true, defaultValue: nil),
            .ownerAnonymousId: Expected(type: .stringAttributeType, optional: true, defaultValue: nil),
            .messageType: Expected(type: .stringAttributeType, optional: false, defaultValue: ""),
            .campaignId: Expected(type: .stringAttributeType, optional: true, defaultValue: nil),
            .createdAt: Expected(type: .dateAttributeType, optional: true, defaultValue: nil),
            .expiresAt: Expected(type: .dateAttributeType, optional: true, defaultValue: nil),
            .priority: Expected(type: .stringAttributeType, optional: true, defaultValue: nil),
            .priorityRank: Expected(type: .integer32AttributeType, optional: false, defaultValue: Int32.max),
            .locationId: Expected(type: .stringAttributeType, optional: true, defaultValue: nil),
            .variantSlug: Expected(type: .stringAttributeType, optional: true, defaultValue: nil),
            .triggerType: Expected(type: .stringAttributeType, optional: true, defaultValue: nil),
            .messageVersion: Expected(type: .stringAttributeType, optional: true, defaultValue: nil),
            .payload: Expected(type: .binaryDataAttributeType, optional: false, defaultValue: nil),
            .insertedAt: Expected(type: .dateAttributeType, optional: false, defaultValue: nil),
            .updatedAt: Expected(type: .dateAttributeType, optional: false, defaultValue: nil)
        ]

        let propertiesByName = entity.attributesByName
        XCTAssertEqual(propertiesByName.count, expected.count, "entity should have exactly the attributes this test expects")

        for (attr, spec) in expected {
            guard let description = propertiesByName[attr.rawValue] else {
                XCTFail("missing attribute \(attr.rawValue)")
                continue
            }
            XCTAssertEqual(description.attributeType, spec.type, "\(attr.rawValue) type")
            XCTAssertEqual(description.isOptional, spec.optional, "\(attr.rawValue) optional")
            switch spec.defaultValue {
            case let expectedString as String:
                XCTAssertEqual(description.defaultValue as? String, expectedString, "\(attr.rawValue) default")
            case let expectedInt as Int32:
                XCTAssertEqual(description.defaultValue as? Int32, expectedInt, "\(attr.rawValue) default")
            default:
                XCTAssertNil(description.defaultValue, "\(attr.rawValue) should have no default")
            }
        }
    }

    func testMessageVersionAttributeNameAvoidsNSObjectVersionCollision() {
        XCTAssertNil(entity.attributesByName["version"])
        XCTAssertNotNil(entity.attributesByName["messageVersion"])
    }

    func testPayloadAllowsExternalBinaryDataStorage() {
        XCTAssertEqual(entity.attributesByName[MessageStoreSchema.Attr.payload.rawValue]?.allowsExternalBinaryDataStorage, true)
    }

    // MARK: - Composite uniqueness constraint

    func testUniquenessConstraintIsCompositeOnMessageIdAndOwnerKey() {
        XCTAssertEqual(entity.uniquenessConstraints.count, 1)
        let constraint = entity.uniquenessConstraints.first ?? []
        let names = constraint.compactMap { $0 as? String }
        XCTAssertEqual(names, [
            MessageStoreSchema.Attr.messageId.rawValue,
            MessageStoreSchema.Attr.ownerKey.rawValue
        ])
    }

    // MARK: - Indexes

    func testAllSixNamedIndexesArePresent() {
        let indexNames = Set(entity.indexes.map { $0.name })
        XCTAssertEqual(indexNames, [
            "idx_owner_message",
            "idx_owner_location_variant",
            "idx_owner_variant",
            "idx_owner_expires",
            "idx_expires",
            "idx_owner_sort"
        ])
    }

    func testIndexElementsMatchExpectedColumnsInOrder() {
        func elementNames(_ indexName: String) -> [String]? {
            entity.indexes.first { $0.name == indexName }?.elements.map { $0.property?.name ?? "" }
        }

        let attr = MessageStoreSchema.Attr.self
        XCTAssertEqual(elementNames("idx_owner_message"), [attr.ownerKey.rawValue, attr.messageId.rawValue])
        XCTAssertEqual(
            elementNames("idx_owner_location_variant"),
            [attr.ownerKey.rawValue, attr.locationId.rawValue, attr.variantSlug.rawValue]
        )
        XCTAssertEqual(elementNames("idx_owner_variant"), [attr.ownerKey.rawValue, attr.variantSlug.rawValue])
        XCTAssertEqual(elementNames("idx_owner_expires"), [attr.ownerKey.rawValue, attr.expiresAt.rawValue])
        XCTAssertEqual(elementNames("idx_expires"), [attr.expiresAt.rawValue])
        XCTAssertEqual(
            elementNames("idx_owner_sort"),
            [attr.ownerKey.rawValue, attr.priorityRank.rawValue, attr.createdAt.rawValue]
        )
    }

    // MARK: - Managed object class

    func testManagedObjectClassNameResolvesBackToHTMessageEntity() {
        let className = entity.managedObjectClassName ?? ""
        let resolved: AnyClass? = NSClassFromString(className)
        XCTAssertNotNil(resolved, "managedObjectClassName (\(className)) should resolve via NSClassFromString")
        XCTAssertTrue(resolved === HTMessageEntity.self)
    }

    /// Pins the real backend response body. A wrong envelope or an empty messageId fails silently on device.

    func testEntityVersionHashSnapshot() {
        let hash = MessageStoreSchema.makeModel().entityVersionHashesByName[MessageStoreSchema.entityName]
        XCTAssertEqual(hash?.base64EncodedString(), MessageStoreSchema_Tests.expectedVersionHashBase64)
    }

    static let expectedVersionHashBase64 = "xV158Mmw0dVMZZc7IRHjR6IppPvKu0e9WHSCc/S/1ZU="
}
#endif
