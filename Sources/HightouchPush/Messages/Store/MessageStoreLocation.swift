import Foundation

/// Where a `MessageStore` keeps its file. Pure Foundation so it stays testable on Linux.
enum MessageStoreLocation {
    enum Location {
        /// `<Application Support>/Hightouch/Messages/messages-v<n>.sqlite`
        case appContainer
        case explicit(URL)
        /// SQLite at `/dev/null`: private to its coordinator, no cleanup needed.
        case ephemeral
    }

    /// `nil` for `.ephemeral`.
    static func storeURL(for location: Location, modelVersion: Int) throws -> URL? {
        switch location {
        case .ephemeral:
            return nil
        case .explicit(let url):
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return url
        case .appContainer:
            let directory = try messagesDirectory()
            return directory.appendingPathComponent(fileName(modelVersion: modelVersion))
        }
    }

    /// The model version is in the filename, so a breaking schema change is a rename rather than
    /// a migration.
    static func fileName(modelVersion: Int) -> String {
        "messages-v\(modelVersion).sqlite"
    }

    /// `<Application Support>/Hightouch/Messages/`, excluded from backup. One store per app: the sandbox
    /// gives each app its own Application Support, except on macOS and Mac Catalyst, where an
    /// unsandboxed app shares it per user, hence the bundle identifier.
    static func messagesDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        var root = base
        #if os(macOS) || targetEnvironment(macCatalyst)
        root = root.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.hightouch.sdk")
        #endif

        let directory = root
            .appendingPathComponent("Hightouch")
            .appendingPathComponent("Messages")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup(directory)
        return directory
    }

    static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
