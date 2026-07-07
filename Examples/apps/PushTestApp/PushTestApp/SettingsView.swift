import SwiftUI

struct SettingsView: View {
    @Binding var isConfigured: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var writeKey: String = ""
    @State private var apiHost: String = ""
    @State private var appId: String = ""
    @State private var autoClearBadgeOnForeground: Bool = false

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

            TextField("API Host (optional)", text: $apiHost)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(.horizontal)

            TextField("App ID", text: $appId)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(.horizontal)

            Toggle("Auto-clear badge on foreground", isOn: $autoClearBadgeOnForeground)
                .padding(.horizontal)

            Button("Save & Connect") {
                let trimmedKey = writeKey.trimmingCharacters(in: .whitespaces)
                let trimmedHost = apiHost.trimmingCharacters(in: .whitespaces)
                let trimmedAppId = appId.trimmingCharacters(in: .whitespaces)
                // appId is required: without it, push token events carry an empty app_id and
                // push silently fails to associate the device. apiHost stays optional (empty
                // means the default region endpoint).
                guard !trimmedKey.isEmpty, !trimmedAppId.isEmpty else { return }

                UserDefaults.standard.set(trimmedKey, forKey: PushTestAppConfig.writeKeyDefaultsKey)
                UserDefaults.standard.set(trimmedHost, forKey: PushTestAppConfig.apiHostDefaultsKey)
                UserDefaults.standard.set(trimmedAppId, forKey: PushTestAppConfig.appIdDefaultsKey)
                UserDefaults.standard.set(
                    autoClearBadgeOnForeground,
                    forKey: PushTestAppConfig.autoClearBadgeDefaultsKey
                )

                // NOTE: This replaces the previous Analytics instance without flushing it.
                // Any in-flight events on the old pipeline will be orphaned. Acceptable for
                // a test app; a production app would need to flush before re-initializing.
                AppDelegate.initializeHightouchPush(
                    writeKey: trimmedKey,
                    apiHost: trimmedHost,
                    appId: trimmedAppId,
                    autoClearBadgeOnForeground: autoClearBadgeOnForeground
                )
                isConfigured = true
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                writeKey.trimmingCharacters(in: .whitespaces).isEmpty
                    || appId.trimmingCharacters(in: .whitespaces).isEmpty
            )

            if hasDefaults {
                Button("Reset to Defaults") {
                    UserDefaults.standard.removeObject(forKey: PushTestAppConfig.writeKeyDefaultsKey)
                    UserDefaults.standard.removeObject(forKey: PushTestAppConfig.apiHostDefaultsKey)
                    UserDefaults.standard.removeObject(forKey: PushTestAppConfig.appIdDefaultsKey)
                    UserDefaults.standard.removeObject(forKey: PushTestAppConfig.autoClearBadgeDefaultsKey)
                    writeKey = Self.plistWriteKey
                    apiHost = Self.plistApiHost
                    appId = Self.plistAppId
                    autoClearBadgeOnForeground = false
                }
                .foregroundColor(.secondary)
            }
        }
        .onAppear {
            writeKey = PushTestAppConfig.writeKey
            apiHost = PushTestAppConfig.apiHost
            appId = PushTestAppConfig.appId
            autoClearBadgeOnForeground = PushTestAppConfig.autoClearBadgeOnForeground
        }
    }
}
