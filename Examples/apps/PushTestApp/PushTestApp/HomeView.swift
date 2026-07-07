import SwiftUI
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

                    badgeTestingPanel

                    Button("Logout", role: .destructive) {
                        HightouchPush.logout()
                        isLoggedIn = false
                    }
                    .buttonStyle(.borderedProminent)
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
