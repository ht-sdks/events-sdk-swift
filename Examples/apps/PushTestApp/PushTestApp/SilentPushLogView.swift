import SwiftUI

/// Shows every push whose custom data reached the app: silent pushes delivered in the
/// background, and visible pushes whose data was read on tap.
struct SilentPushLogView: View {
    @ObservedObject private var store = SilentPushStore.shared

    var body: some View {
        Group {
            if store.entries.isEmpty {
                VStack(spacing: 8) {
                    Text("No push data received yet")
                        .font(.headline)
                    Text("Send a silent push with custom data, or tap a visible push that carries custom data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                List(store.entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.source == .silent ? "Silent" : "Tapped")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(entry.source == .silent ? Color.purple.opacity(0.2) : Color.blue.opacity(0.2))
                                .clipShape(Capsule())
                            Spacer()
                            Text(entry.receivedAt, format: .dateTime.hour().minute().second())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        ForEach(entry.customData.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack(alignment: .top) {
                                Text(key)
                                    .font(.caption.bold())
                                Text(value)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Push data")
        .toolbar {
            if !store.entries.isEmpty {
                Button("Clear") {
                    store.clear()
                }
            }
        }
    }
}
