import SwiftUI
import HightouchPush

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @Binding var isConfigured: Bool
    @State private var userId: String = ""
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Push Test App")
                    .font(.title)

                TextField("User ID", text: $userId)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding(.horizontal)
                    .accessibilityIdentifier("login.userIdField")

                Button("Login") {
                    let trimmed = userId.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    HightouchPush.identify(userId: trimmed)
                    isLoggedIn = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(userId.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("login.loginButton")

                // The SDK stores the data collection choice per write key, so rebuild the panel
                // when the settings sheet switches keys.
                DataCollectionPanel()
                    .id(PushTestAppConfig.writeKey)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isConfigured: $isConfigured)
        }
    }
}
