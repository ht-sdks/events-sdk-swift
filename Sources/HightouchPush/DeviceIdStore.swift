import Foundation

/// Stores this install's device ID: a UUID minted on first use and kept until the app is
/// uninstalled.
///
/// The file lives in Application Support and is excluded from backup, so restoring a backup or
/// transferring to another device does not copy the ID. It is separate from `UserDefaults` and
/// analytics storage, so logout and `reset()` cannot remove it.
final class DeviceIdStore {
    static let shared = DeviceIdStore(fileURL: DeviceIdStore.defaultFileURL)

    private let fileURL: () throws -> URL
    private let lock = NSLock()
    private var cached: String?

    init(fileURL: @escaping () throws -> URL) {
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
                } catch {
                    print("[HightouchPush] Could not read the device ID; events omit it until it is readable: \(error)")
                    return nil
                }
                if !stored.isEmpty {
                    return stored
                }
            }
            try minted.write(to: url, atomically: true, encoding: .utf8)
            MessageStoreLocation.excludeFromBackup(url)
        } catch {
            print("[HightouchPush] Could not store the device ID; it will change on the next launch: \(error)")
        }
        return minted
    }

    /// `<Application Support>/Hightouch/device-id`
    static func defaultFileURL() throws -> URL {
        try MessageStoreLocation.hightouchDirectory().appendingPathComponent("device-id")
    }
}
