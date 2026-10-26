import Foundation

/// Where a `MessageStore` keeps its file. Pure Foundation so it stays testable on Linux.
enum MessageStoreLocation {
    enum Location {
        /// `<Application Support>/Hightouch/Messages/<safeWriteKey>/messages-v<n>.sqlite`
        case appContainer
        case explicit(URL)
        /// SQLite at `/dev/null`: private to its coordinator, no cleanup needed.
        case ephemeral
    }

    /// Write keys can contain `/`, which would otherwise create nested directories.
    static func safeWriteKey(_ writeKey: String) -> String {
        writeKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? writeKey
    }

    /// `nil` for `.ephemeral`.
    static func storeURL(for location: Location, writeKey: String, modelVersion: Int) throws -> URL? {
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
            let directory = try messagesDirectory(writeKey: writeKey)
            return directory.appendingPathComponent(fileName(modelVersion: modelVersion))
        }
    }

    /// The model version is in the filename, so a breaking schema change is a rename rather than
    /// a migration.
    static func fileName(modelVersion: Int) -> String {
        "messages-v\(modelVersion).sqlite"
    }

    /// `<Application Support>/Hightouch/Messages/<safeWriteKey>/`, excluded from backup. On macOS
    /// Application Support is shared per user, hence the bundle identifier.
    static func messagesDirectory(writeKey: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        var root = base
        #if os(macOS)
        root = root.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.hightouch.sdk")
        #endif

        let directory = root
            .appendingPathComponent("Hightouch")
            .appendingPathComponent("Messages")
            .appendingPathComponent(safeWriteKey(writeKey))

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
