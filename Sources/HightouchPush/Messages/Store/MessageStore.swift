import Foundation

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

/// The Core Data-backed local cache of messages for this app, shared by every write key.
final class MessageStore {
    typealias Location = MessageStoreLocation.Location

    let container: NSPersistentContainer

    /// All mutations, inside `perform`. Trump merge policy: the server is the source of truth.
    let writeContext: NSManagedObjectContext

    /// All reads, inside `performAndWait`.
    let readContext: NSManagedObjectContext

    init(location: Location) throws {
        let modelVersion = MessageStoreSchema.modelVersion
        let model = MessageStoreSchema.makeModel()
        let container = NSPersistentContainer(name: "HightouchMessages", managedObjectModel: model)

        let storeURL = try MessageStore.resolveStoreURL(location: location, modelVersion: modelVersion)
        let description = MessageStore.makeStoreDescription(url: storeURL)
        container.persistentStoreDescriptions = [description]

        try MessageStore.loadStore(container: container, description: description)

        self.container = container

        let writeContext = container.newBackgroundContext()
        writeContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        writeContext.automaticallyMergesChangesFromParent = false
        writeContext.undoManager = nil
        self.writeContext = writeContext

        let readContext = container.newBackgroundContext()
        readContext.automaticallyMergesChangesFromParent = true
        readContext.stalenessInterval = 0
        readContext.undoManager = nil
        self.readContext = readContext

        if case .appContainer = location {
            MessageStore.pruneOldModelVersions(currentVersion: modelVersion)
        }
    }

    // MARK: - Setup helpers

    private static func resolveStoreURL(location: Location, modelVersion: Int) throws -> URL {
        if let url = try MessageStoreLocation.storeURL(for: location, modelVersion: modelVersion) {
            return url
        }
        // `.ephemeral`: SQLite at /dev/null, not NSInMemoryStoreType, which ignores uniqueness
        // constraints and throws on NSBatchDeleteRequest.
        return URL(fileURLWithPath: "/dev/null")
    }

    private static func makeStoreDescription(url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(["journal_mode": "WAL"] as NSObject, forKey: NSSQLitePragmasOption)
        #if os(iOS) || targetEnvironment(macCatalyst)
        // With the default (complete) protection, a process background-launched by a silent push
        // before first unlock can't open the store.
        description.setOption(
            FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )
        #endif
        return description
    }

    /// On any load failure, destroys the store and retries once from empty: every row is
    /// re-fetchable from the server.
    private static func loadStore(container: NSPersistentContainer, description: NSPersistentStoreDescription) throws {
        guard MessageStore.loadOnce(container: container) != nil else { return }

        if let url = description.url {
            try? container.persistentStoreCoordinator.destroyPersistentStore(
                at: url, ofType: description.type, options: nil
            )
        }

        if let retryError = MessageStore.loadOnce(container: container) {
            throw retryError
        }
    }

    private static func loadOnce(container: NSPersistentContainer) -> Error? {
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        return loadError
    }

    /// Deletes store files (and sidecars) left behind by older model versions.
    private static func pruneOldModelVersions(currentVersion: Int) {
        guard let directory = try? MessageStoreLocation.messagesDirectory() else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }

        let currentPrefix = MessageStoreLocation.fileName(modelVersion: currentVersion)
        for fileURL in contents {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("messages-v"), !name.hasPrefix(currentPrefix) else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
#endif
