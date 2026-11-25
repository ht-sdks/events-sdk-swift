import Foundation

/// Stores this install's device ID: a UUID minted on first use and kept until the app is
/// uninstalled.
///
/// The file lives in Application Support and is excluded from backup, so restoring a backup or
/// transferring to another device does not copy the ID. It is separate from `UserDefaults` and
/// analytics storage, so logout and `reset()` cannot remove it.
final class DeviceIdStore: @unchecked Sendable {
    static let shared = DeviceIdStore(fileURL: DeviceIdStore.defaultFileURL)

    private let fileURL: @Sendable () throws -> URL
    private let lock = NSLock()
    private var cached: String?

    init(fileURL: @escaping @Sendable () throws -> URL) {
        self.fileURL = fileURL
    }

    /// Returns the stored ID, minting and storing one if none exists.
    ///
    /// `nil` while a stored ID exists but cannot be read, as after a restart before the first
    /// unlock: minting then would report this install under a second ID.
    func getOrCreate() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let deviceId = loadOrMint()
        cached = deviceId
        return deviceId
    }

    private func loadOrMint() -> String? {
        let minted = UUID().uuidString
        do {
            let url = try fileURL()
            if FileManager.default.fileExists(atPath: url.path) {
                let stored: String
                do {
                    stored = try String(contentsOf: url, encoding: .utf8)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    print("[HightouchPush] Could not read the device ID; events omit it until it is readable: \(error)")
                    return nil
                }
                if !stored.isEmpty {
                    return stored
                }
            }

            #if os(iOS) || os(tvOS) || os(watchOS)
            let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            #else
            let writeOptions: Data.WritingOptions = [.atomic]
            #endif

            try Data(minted.utf8).write(to: url, options: writeOptions)
            MessageStoreLocation.excludeFromBackup(url)
        } catch where Self.isPermissionError(error) {
            print("[HightouchPush] Device ID storage is unavailable; events omit it until readable: \(error)")
            return nil
        } catch {
            print("[HightouchPush] Could not store the device ID; it will change on the next launch: \(error)")
        }
        return minted
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        if let cocoaError = error as? CocoaError,
           cocoaError.code == .fileReadNoPermission || cocoaError.code == .fileWriteNoPermission {
            return true
        }
        if let posixError = error as? POSIXError,
           posixError.code == .EPERM || posixError.code == .EACCES {
            return true
        }
        if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
            return isPermissionError(underlying)
        }
        return false
    }

    /// `<Application Support>/Hightouch/device-id`
    static func defaultFileURL() throws -> URL {
        try MessageStoreLocation.hightouchDirectory().appendingPathComponent("device-id")
    }
}
