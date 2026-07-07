import SwiftUI
import HightouchPush

struct HomeView: View {
    @Binding var isLoggedIn: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Logged in as: \(HightouchPush.userId ?? "unknown")")
                Text("Anonymous ID: \(HightouchPush.anonymousId)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                NavigationLink("Push data log") {
                    SilentPushLogView()
                }

                Button("Logout", role: .destructive) {
                    HightouchPush.logout()
                    isLoggedIn = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
