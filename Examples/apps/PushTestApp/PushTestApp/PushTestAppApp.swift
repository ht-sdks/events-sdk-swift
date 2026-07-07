import SwiftUI
import Hightouch
import HightouchPush

/// Single source of truth for the app's stored configuration: UserDefaults override first,
/// then Info.plist build-time default.
enum PushTestAppConfig {
    static let writeKeyDefaultsKey = "ht_write_key"
    static let apiHostDefaultsKey = "ht_api_host"
    static let appIdDefaultsKey = "ht_app_id"
    static let autoClearBadgeDefaultsKey = "ht_auto_clear_badge_on_foreground"

    static func value(userDefaultsKey: String, plistKey: String) -> String {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey), !saved.isEmpty {
            return saved
        }
        return Bundle.main.infoDictionary?[plistKey] as? String ?? ""
    }

    static var writeKey: String {
        value(userDefaultsKey: writeKeyDefaultsKey, plistKey: "HightouchWriteKey")
    }

    static var apiHost: String {
        value(userDefaultsKey: apiHostDefaultsKey, plistKey: "HightouchApiHost")
    }

    static var appId: String {
        value(userDefaultsKey: appIdDefaultsKey, plistKey: "HightouchAppId")
    }

    static var autoClearBadgeOnForeground: Bool {
        UserDefaults.standard.bool(forKey: autoClearBadgeDefaultsKey)
    }
}

@main
struct PushTestAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isLoggedIn = false
    // Both writeKey and appId are required — an empty appId silently breaks push
    // association, so it can't be treated as "configured."
    @State private var isConfigured: Bool =
        !PushTestAppConfig.writeKey.trimmingCharacters(in: .whitespaces).isEmpty
        && !PushTestAppConfig.appId.trimmingCharacters(in: .whitespaces).isEmpty

    var body: some Scene {
        WindowGroup {
            Group {
                if !isConfigured {
                    SettingsView(isConfigured: $isConfigured)
                } else if isLoggedIn {
                    HomeView(isLoggedIn: $isLoggedIn)
                } else {
                    NavigationStack {
                        LoginView(isLoggedIn: $isLoggedIn, isConfigured: $isConfigured)
                    }
                }
            }
            .onAppear {
                isLoggedIn = HightouchPush.userId != nil
            }
        }
    }
}

/// Receives silent-push custom data and logs it for the in-app "Push data" view.
/// Held in a static so it outlives the weak reference the SDK config keeps.
final class SilentPushHandler: HightouchSilentPushDelegate {
    func receive(customData: [String: String]) async {
        print("[PushTestApp] Silent push received: \(customData)")
        SilentPushStore.shared.append(source: .silent, customData: customData)
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    static let silentPushHandler = SilentPushHandler()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        _ = AppDelegate.initializeFromStoredConfig()
        // apiHost stays optional (empty = default region). If writeKey or appId is missing,
        // SettingsView will call initializeHightouchPush after the user enters config.

        return true
    }

    /// (Re)initialize from stored config. Preserves the currently identified test user across
    /// re-initialization so toggling config (e.g. auto-clear badge) doesn't log the user out.
    @discardableResult
    static func initializeFromStoredConfig() -> Bool {
        let writeKey = PushTestAppConfig.writeKey
        let appId = PushTestAppConfig.appId
        guard !writeKey.isEmpty, !appId.isEmpty else { return false }
        let currentUserId = HightouchPush.userId
        initializeHightouchPush(
            writeKey: writeKey,
            apiHost: PushTestAppConfig.apiHost,
            appId: appId,
            autoClearBadgeOnForeground: PushTestAppConfig.autoClearBadgeOnForeground
        )
        if let currentUserId {
            HightouchPush.identify(userId: currentUserId)
        }
        return true
    }

    static func initializeHightouchPush(
        writeKey: String,
        apiHost: String,
        appId: String,
        autoClearBadgeOnForeground: Bool
    ) {
        var pushConfig = HightouchPushConfig(appId: appId)
        pushConfig.silentPushDelegate = silentPushHandler
        pushConfig.autoClearBadgeOnForeground = autoClearBadgeOnForeground

        let analyticsConfig = Configuration(writeKey: writeKey)
            .trackApplicationLifecycleEvents(true)
        if !apiHost.isEmpty {
            analyticsConfig.apiHost(apiHost)
        }
        HightouchPush.initialize(configuration: analyticsConfig, config: pushConfig)

        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                print("[PushTestApp] Notification permission error: \(error)")
            }
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - APNs Token

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[PushTestApp] APNs token: \(hex)")
        HightouchPush.register(token: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[PushTestApp] Failed to register for remote notifications: \(error)")
    }

    // MARK: - Background/Silent Push

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        HightouchAppIntegration.application(
            application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler
        )
    }

    // MARK: - Foreground Notification Presentation

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // MARK: - Notification Response (tap)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Read the tapped push's custom data and log it alongside silent deliveries.
        if let customData = HightouchAppIntegration.customData(from: response), !customData.isEmpty {
            SilentPushStore.shared.append(source: .tap, customData: customData)
        }

        HightouchAppIntegration.userNotificationCenter(
            center, didReceive: response, withCompletionHandler: completionHandler
        )
    }
}
