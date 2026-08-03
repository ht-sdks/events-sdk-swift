import XCTest
@testable import Hightouch
@testable import HightouchPush

/// `initialize` arms the device-token plugin from the cached APNs token, so cold-start
/// events still carry `context.device.token`.
final class HightouchPushInitTokenArming_Tests: XCTestCase {

    private let apnsKey = "com.hightouch.push.apnsToken"
    private let lastUploadKey = "com.hightouch.push.lastTokenUploadAt"
    private let cachedToken = Data([0xde, 0xad, 0xbe, 0xef])

    /// `HightouchPush.analytics` hard-asserts when uninitialized; guards tearDown.
    private var initialized = false

    override func tearDown() {
        if initialized {
            HightouchPush.analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        }
        UserDefaults.standard.removeObject(forKey: apnsKey)
        UserDefaults.standard.removeObject(forKey: lastUploadKey)
        super.tearDown()
    }

    /// Initialize with a per-test write key and attach an output reader. Seed the token
    /// cache BEFORE calling — arming reads UserDefaults during initialize.
    private func initializeAndAttachOutput() -> OutputReaderPlugin {
        initialized = true
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-init-arming"),
            config: HightouchPushConfig(appId: "init-arming-app")
        )
        let output = OutputReaderPlugin()
        HightouchPush.analytics.add(plugin: output)
        waitUntilStarted(analytics: HightouchPush.analytics)
        return output
    }

    private func deviceToken(of event: RawEvent?) -> String? {
        event?.context?.dictionaryValue?[keyPath: "device.token"] as? String
    }

    func testInitializeArmsDeviceTokenFromCache() {
        UserDefaults.standard.set(cachedToken, forKey: apnsKey)
        let output = initializeAndAttachOutput()

        HightouchPush.analytics.track(name: "cold start open")

        let event = output.events.compactMap { $0 as? TrackEvent }.last
        XCTAssertEqual(
            deviceToken(of: event),
            "deadbeef",
            "event dispatched before any register() call should carry the cached token"
        )
    }

    func testInitializeWithoutCachedTokenLeavesEventsUnstamped() {
        UserDefaults.standard.removeObject(forKey: apnsKey)
        let output = initializeAndAttachOutput()

        HightouchPush.analytics.track(name: "no token yet")

        let event = output.events.compactMap { $0 as? TrackEvent }.last
        XCTAssertNotNil(event)
        XCTAssertNil(deviceToken(of: event), "no cached token → no device.token on events")
    }

    func testRegisterOverwritesCacheArmedToken() {
        UserDefaults.standard.set(cachedToken, forKey: apnsKey)
        let output = initializeAndAttachOutput()

        HightouchPush.register(token: Data([0x01, 0x02]))
        HightouchPush.analytics.track(name: "after register")

        let event = output.events.compactMap { $0 as? TrackEvent }.last
        XCTAssertEqual(
            deviceToken(of: event),
            "0102",
            "register(token:) should replace the cache-armed token with the fresh one"
        )
    }
}
