import Foundation

/// One received push's custom data, as shown in the in-app log.
struct PushDataLogEntry: Identifiable, Codable {
    enum Source: String, Codable {
        /// Delivered by a silent push while the app was in the background.
        case silent
        /// Read from a visible push the user tapped.
        case tap
    }

    let id: UUID
    let receivedAt: Date
    let source: Source
    let customData: [String: String]
}

/// Persists received custom-data entries in UserDefaults so entries written while iOS wakes
/// the app in the background survive until the UI is next shown.
final class SilentPushStore: ObservableObject {
    static let shared = SilentPushStore()

    @Published private(set) var entries: [PushDataLogEntry] = []

    private static let defaultsKey = "ht_push_data_log"

    // Serializes every load-modify-save so a silent-push append (concurrency pool thread)
    // can't race a tap append or clear (main thread) and lose a write.
    private let queue = DispatchQueue(label: "com.hightouch.PushTestApp.silent-push-store")

    private init() {
        entries = Self.load()
    }

    func append(source: PushDataLogEntry.Source, customData: [String: String]) {
        let entry = PushDataLogEntry(
            id: UUID(), receivedAt: Date(), source: source, customData: customData
        )
        // Write to UserDefaults before returning: iOS may suspend the app right after a
        // background wake completes, so the entry must be on disk when the delegate returns.
        queue.sync {
            var current = Self.load()
            current.insert(entry, at: 0)
            Self.save(current)
            DispatchQueue.main.async {
                self.entries = current
            }
        }
    }

    func clear() {
        queue.sync {
            Self.save([])
            DispatchQueue.main.async {
                self.entries = []
            }
        }
    }

    private static func load() -> [PushDataLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([PushDataLogEntry].self, from: data)) ?? []
    }

    private static func save(_ entries: [PushDataLogEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
