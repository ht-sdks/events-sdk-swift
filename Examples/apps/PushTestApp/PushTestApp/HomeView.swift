import SwiftUI
import UIKit
import UserNotifications
import HightouchPush

struct HomeView: View {
    @Binding var isLoggedIn: Bool
    @State private var badgeCount: String = "3"
    @State private var badgeStatus: String = "Set a badge, background the app, then inspect the app icon."
    @State private var autoClearBadgeOnForeground: Bool = PushTestAppConfig.autoClearBadgeOnForeground

    private var parsedBadgeCount: Int? {
        Int(badgeCount.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Logged in as: \(HightouchPush.userId ?? "unknown")")
                    Text("Anonymous ID: \(HightouchPush.anonymousId)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    NavigationLink("Push data log") {
                        SilentPushLogView()
                    }

                    Divider()

                    // wipeData() logs the user out, so return to the login screen like Logout does.
                    DataCollectionPanel(onWipe: { isLoggedIn = false })

                    badgeTestingPanel

                    Button("Logout", role: .destructive) {
                        HightouchPush.logout()
                        isLoggedIn = false
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("home.logoutButton")
                }
                .padding()
            }
        }
        .onAppear {
            autoClearBadgeOnForeground = PushTestAppConfig.autoClearBadgeOnForeground
        }
    }

    private var badgeTestingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Badge Testing")
                .font(.headline)

            TextField("Badge count", text: $badgeCount)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)

            HStack {
                Button("Set Badge") {
                    setBadge()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedBadgeCount == nil)

                Button("Reset Badge") {
                    resetBadge()
                }
                .buttonStyle(.bordered)
            }

            Toggle("Auto-clear on foreground", isOn: Binding(
                get: { autoClearBadgeOnForeground },
                set: { newValue in
                    autoClearBadgeOnForeground = newValue
                    UserDefaults.standard.set(
                        newValue,
                        forKey: PushTestAppConfig.autoClearBadgeDefaultsKey
                    )
                    AppDelegate.initializeFromStoredConfig()
                    badgeStatus = newValue
                        ? "Auto-clear enabled. Set a badge, background, then reopen the app."
                        : "Auto-clear disabled."
                }
            ))

            Text(badgeStatus)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func setBadge() {
        guard let count = parsedBadgeCount else { return }
        Task {
            await HightouchPush.setBadge(count)
            await MainActor.run {
                badgeStatus = "Set badge to \(max(0, count)). Background the app to inspect the icon."
            }
        }
    }

    private func resetBadge() {
        Task {
            await HightouchPush.resetBadge()
            await MainActor.run {
                badgeStatus = "Reset badge to 0. Background the app to confirm it cleared."
            }
        }
    }
}

/// A snapshot of the SDK state the data collection panel displays.
struct SDKStatus {
    var isDataCollectionEnabled: Bool
    var userId: String?
    var anonymousId: String
    var deviceId: String?
    var apnsTokenHex: String?
    var apnsRegistrationError: String?

    static func read() -> SDKStatus {
        SDKStatus(
            isDataCollectionEnabled: HightouchPush.isDataCollectionEnabled,
            userId: HightouchPush.userId,
            anonymousId: HightouchPush.anonymousId,
            deviceId: readDeviceId(),
            apnsTokenHex: UserDefaults.standard.string(forKey: PushTestAppConfig.apnsTokenDefaultsKey),
            apnsRegistrationError: UserDefaults.standard.string(
                forKey: PushTestAppConfig.apnsRegistrationErrorDefaultsKey
            )
        )
    }

    /// `HightouchPush.deviceId` is internal to the SDK, so this reads the file its `DeviceIdStore`
    /// writes: `<Application Support>/Hightouch/device-id` (under the bundle ID on Mac Catalyst).
    /// The SDK creates it with the first push event, so it is absent on a fresh install until then.
    private static func readDeviceId() -> String? {
        guard var url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        #if targetEnvironment(macCatalyst)
        url = url.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.hightouch.sdk")
        #endif
        url = url.appendingPathComponent("Hightouch").appendingPathComponent("device-id")
        guard let stored = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Data collection controls and a live view of the SDK state they change. Shown on both the
/// login and home screens so collection can be turned back on before logging in after a wipe.
struct DataCollectionPanel: View {
    /// Called after `wipeData()`, which logs the user out.
    var onWipe: () -> Void = {}

    @State private var status = SDKStatus.read()
    @State private var pushPermission = "checking…"
    @State private var lastAction: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Collection")
                .font(.headline)

            statusRow(
                "Data Collection Enabled",
                value: status.isDataCollectionEnabled ? "true" : "false",
                identifier: "status.dataCollectionEnabled",
                valueColor: status.isDataCollectionEnabled ? .green : .red
            )
            statusRow("User ID", value: status.userId ?? "none", identifier: "status.userId")
            statusRow("Anonymous ID", value: status.anonymousId, identifier: "status.anonymousId")
            statusRow(
                "Device ID",
                value: status.deviceId ?? "not created yet",
                identifier: "status.deviceId"
            )
            statusRow("Push Permission", value: pushPermission, identifier: "status.pushPermission")
            statusRow("APNs Token", value: apnsTokenDescription, identifier: "status.apnsToken")

            HStack {
                Button {
                    setDataCollectionEnabled(false)
                } label: {
                    Text("Stop Data Collection")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("dataCollection.stopButton")

                Button {
                    setDataCollectionEnabled(true)
                } label: {
                    Text("Start Data Collection")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("dataCollection.startButton")
            }

            Button(role: .destructive) {
                wipeData()
            } label: {
                Text("Wipe Data")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("dataCollection.wipeButton")

            Text(lastAction ?? hint)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("dataCollection.lastAction")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .onAppear {
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushTestAppRegistrationDidChange)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var apnsTokenDescription: String {
        if let token = status.apnsTokenHex {
            return token
        }
        if let error = status.apnsRegistrationError {
            return "registration failed: \(error)"
        }
        return "not received yet"
    }

    private var hint: String {
        status.isDataCollectionEnabled
            ? "Stop pauses collection and keeps the user. Wipe Data also asks Hightouch to delete this device's record and logs out."
            : "Data collection is off: events are dropped on this device. Tap Start Data Collection before logging in to resume."
    }

    private func statusRow(
        _ label: String,
        value: String,
        identifier: String,
        valueColor: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(valueColor)
                .textSelection(.enabled)
                .accessibilityIdentifier(identifier)
        }
    }

    private func setDataCollectionEnabled(_ enabled: Bool) {
        HightouchPush.setDataCollectionEnabled(enabled)
        lastAction = enabled
            ? "Started data collection. A held APNs token is registered again for the current user."
            : "Stopped data collection. Events are dropped on this device; the user is kept."
        refresh()
    }

    private func wipeData() {
        let wipedUser = HightouchPush.userId ?? "anonymous device"
        HightouchPush.wipeData()
        lastAction = "Wiped \(wipedUser): sent \"deleted\", stopped data collection and logged out."
        refresh()
        onWipe()
    }

    private func refresh() {
        status = SDKStatus.read()
        Task {
            let description = await Self.pushPermissionDescription()
            await MainActor.run {
                pushPermission = description
            }
        }
    }

    nonisolated private static func pushPermissionDescription() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return "not determined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        default: return "other (\(settings.authorizationStatus.rawValue))"
        }
    }
}
