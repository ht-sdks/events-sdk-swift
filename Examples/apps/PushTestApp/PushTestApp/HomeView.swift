import SwiftUI
import HightouchPush

struct HomeView: View {
    @Binding var isLoggedIn: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Logged in as: \(HightouchPush.userId ?? "unknown")")
            Text("Anonymous ID: \(HightouchPush.anonymousId)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Logout", role: .destructive) {
                HightouchPush.logout()
                isLoggedIn = false
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
