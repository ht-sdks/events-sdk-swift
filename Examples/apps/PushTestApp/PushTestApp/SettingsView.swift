import SwiftUI

struct SettingsView: View {
    @Binding var isConfigured: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var writeKey: String = ""
    @State private var apiHost: String = ""
    @State private var appId: String = ""

    /// Read a config value: UserDefaults override first, then Info.plist build-time default.
    private static func configValue(userDefaultsKey: String, plistKey: String) -> String {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey), !saved.isEmpty {
            return saved
        }
        return Bundle.main.infoDictionary?[plistKey] as? String ?? ""
    }

    private static var plistWriteKey: String {
        Bundle.main.infoDictionary?["HightouchWriteKey"] as? String ?? ""
    }
    private static var plistApiHost: String {
        Bundle.main.infoDictionary?["HightouchApiHost"] as? String ?? ""
    }
    private static var plistAppId: String {
        Bundle.main.infoDictionary?["HightouchAppId"] as? String ?? ""
    }

    private var hasDefaults: Bool {
        !Self.plistWriteKey.isEmpty || !Self.plistApiHost.isEmpty || !Self.plistAppId.isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Configuration")
                .font(.title)

            TextField("Write Key", text: $writeKey)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(.horizontal)

            TextField("API Host", text: $apiHost)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(.horizontal)

            TextField("App ID", text: $appId)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(.horizontal)

            Button("Save & Connect") {
                let trimmedKey = writeKey.trimmingCharacters(in: .whitespaces)
                let trimmedHost = apiHost.trimmingCharacters(in: .whitespaces)
                let trimmedAppId = appId.trimmingCharacters(in: .whitespaces)
                guard !trimmedKey.isEmpty else { return }

                UserDefaults.standard.set(trimmedKey, forKey: "ht_write_key")
                UserDefaults.standard.set(trimmedHost, forKey: "ht_api_host")
                UserDefaults.standard.set(trimmedAppId, forKey: "ht_app_id")

                // NOTE: This replaces the previous Analytics instance without flushing it.
                // Any in-flight events on the old pipeline will be orphaned. Acceptable for
                // a test app; a production app would need to flush before re-initializing.
                AppDelegate.initializeHightouchPush(
                    writeKey: trimmedKey,
                    apiHost: trimmedHost,
                    appId: trimmedAppId
                )
                isConfigured = true
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(writeKey.trimmingCharacters(in: .whitespaces).isEmpty)

            if hasDefaults {
                Button("Reset to Defaults") {
                    UserDefaults.standard.removeObject(forKey: "ht_write_key")
                    UserDefaults.standard.removeObject(forKey: "ht_api_host")
                    UserDefaults.standard.removeObject(forKey: "ht_app_id")
                    writeKey = Self.plistWriteKey
                    apiHost = Self.plistApiHost
                    appId = Self.plistAppId
                }
                .foregroundColor(.secondary)
            }
        }
        .onAppear {
            writeKey = Self.configValue(userDefaultsKey: "ht_write_key", plistKey: "HightouchWriteKey")
            apiHost = Self.configValue(userDefaultsKey: "ht_api_host", plistKey: "HightouchApiHost")
            appId = Self.configValue(userDefaultsKey: "ht_app_id", plistKey: "HightouchAppId")
        }
    }
}
