import SwiftUI
import Hightouch
import HightouchPush

@main
struct PushTestAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isLoggedIn = false
    @State private var isConfigured: Bool = {
        // Both writeKey and appId are required — an empty appId silently breaks push
        // association, so it can't be treated as "configured."
        let savedWriteKey = UserDefaults.standard.string(forKey: "ht_write_key")?.trimmingCharacters(in: .whitespaces) ?? ""
        let savedAppId = UserDefaults.standard.string(forKey: "ht_app_id")?.trimmingCharacters(in: .whitespaces) ?? ""
        if !savedWriteKey.isEmpty, !savedAppId.isEmpty {
            return true
        }
        // Also consider configured if build-time defaults are present in Info.plist
        let plistWriteKey = Bundle.main.infoDictionary?["HightouchWriteKey"] as? String ?? ""
        let plistAppId = Bundle.main.infoDictionary?["HightouchAppId"] as? String ?? ""
        if !plistWriteKey.isEmpty, !plistAppId.isEmpty {
            return true
        }
        return false
    }()

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

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Initialize from UserDefaults if available, otherwise fall back to Info.plist build-time defaults.
        let writeKey = UserDefaults.standard.string(forKey: "ht_write_key")
            ?? Bundle.main.infoDictionary?["HightouchWriteKey"] as? String
            ?? ""
        let apiHost = UserDefaults.standard.string(forKey: "ht_api_host")
            ?? Bundle.main.infoDictionary?["HightouchApiHost"] as? String
            ?? ""
        let appId = UserDefaults.standard.string(forKey: "ht_app_id")
            ?? Bundle.main.infoDictionary?["HightouchAppId"] as? String
            ?? ""

        if !writeKey.isEmpty, !appId.isEmpty {
            AppDelegate.initializeHightouchPush(writeKey: writeKey, apiHost: apiHost, appId: appId)
        }
        // apiHost stays optional (empty = default region). If writeKey or appId is missing,
        // SettingsView will call initializeHightouchPush after the user enters config.

        return true
    }

    static func initializeHightouchPush(writeKey: String, apiHost: String, appId: String) {
        let pushConfig = HightouchPushConfig(appId: appId)

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
        HightouchAppIntegration.userNotificationCenter(
            center, didReceive: response, withCompletionHandler: completionHandler
        )
    }
}
