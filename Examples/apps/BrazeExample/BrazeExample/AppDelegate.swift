//
//  AppDelegate.swift
//  BrazeExample
//

import UIKit
import Hightouch
import HightouchBraze
import BrazeKit
import BrazeUI

// flip and relaunch to log one purchase per order.
let perOrder = false

let brazeAPIKey = "BRAZE_API_KEY"
let hightouchWriteKey = "HT_WRITE_KEY"
let brazeEndpoint = "sdk.iad-03.braze.com"
let hightouchAPIHost = "us-east-1.hightouch-events.com/v1"

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var analytics: Analytics? = nil

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Analytics.debugLogsEnabled = true

        let configuration = Configuration(writeKey: hightouchWriteKey)
            .apiHost(hightouchAPIHost)
            .flushInterval(10)
            .flushAt(2)

        analytics = Analytics(configuration: configuration)

        var options = BrazeDestination.Options(
            purchaseDetection: .eventNames(["Order Completed", "Completed Order", "Membership Purchased"]),
            forwardScreenViews: true
        )
        if perOrder {
            options.purchaseGrouping = .perOrder
        }

        let brazeDestination = BrazeDestination(
            apiKey: brazeAPIKey,
            endpoint: brazeEndpoint,
            options: options,
            configure: { $0.logger.level = .info }
        )
        brazeDestination.onReady { braze in
            braze.inAppMessagePresenter = BrazeInAppMessageUI()
            braze.configuration.logger.level = .info
        }
        analytics?.add(plugin: brazeDestination)

        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}

extension UIApplicationDelegate {
    var analytics: Analytics? {
        if let appDelegate = self as? AppDelegate {
            return appDelegate.analytics
        }
        return nil
    }
}
