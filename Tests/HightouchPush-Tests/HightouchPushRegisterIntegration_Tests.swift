import XCTest
@testable import Hightouch
@testable import HightouchPush

/// Integration tests that drive the real `HightouchPush.register(token:)` against a real
/// `Analytics`, verifying the dedupe + TTL-heartbeat gating. Uploads are confirmed two ways: an
/// `OutputReaderPlugin` captures the dispatched `CEP Push Token Events`, and the persisted
/// `com.hightouch.push.lastTokenUploadAt` timestamp (written only when `register` uploads) is the
/// dedupe/cache signal.
final class HightouchPushRegisterIntegration_Tests: XCTestCase {

    private let lastUploadKey = "com.hightouch.push.lastTokenUploadAt"
    private let apnsKey = "com.hightouch.push.apnsToken"
    private let tokenA = Data([0x01, 0x02, 0x03, 0x04])
    private let tokenB = Data([0x0a, 0x0b, 0x0c, 0x0d])
    private var output: OutputReaderPlugin!

    override func setUp() {
        super.setUp()
        // Clean slate: no cached token, never-uploaded. Then initialize (unique write key for
        // storage isolation) so the SDK reloads state from the cleared defaults.
        UserDefaults.standard.removeObject(forKey: lastUploadKey)
        UserDefaults.standard.removeObject(forKey: apnsKey)
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-reg-integration"),
            config: HightouchPushConfig(appId: "reg-integration-app")
        )
        output = OutputReaderPlugin()
        HightouchPush.analytics.add(plugin: output)
        // Ensure the startup queue has drained so subsequent events flow synchronously to `output`.
        waitUntilStarted(analytics: HightouchPush.analytics)
    }

    override func tearDown() {
        HightouchPush.analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        UserDefaults.standard.removeObject(forKey: lastUploadKey)
        UserDefaults.standard.removeObject(forKey: apnsKey)
        super.tearDown()
    }

    private var stamp: Double { UserDefaults.standard.double(forKey: lastUploadKey) }

    /// Count of `CEP Push Token Events` actually dispatched. These tests never log out, so every
    /// such event is a "registered" upload.
    private var uploadCount: Int {
        output.events.compactMap { $0 as? TrackEvent }
            .filter { $0.event == "CEP Push Token Events" }
            .count
    }

    func testFirstRegisterUploadsAndStamps() {
        XCTAssertEqual(uploadCount, 0, "precondition: nothing dispatched yet")
        XCTAssertEqual(stamp, 0, "precondition: never uploaded")

        HightouchPush.register(token: tokenA)

        XCTAssertEqual(uploadCount, 1, "first register should dispatch one event")
        XCTAssertGreaterThan(stamp, 0, "and stamp the upload time")
    }

    func testUnchangedTokenWithinTTLIsDeduped() {
        HightouchPush.register(token: tokenA)
        XCTAssertEqual(uploadCount, 1)
        let first = stamp

        HightouchPush.register(token: tokenA)

        XCTAssertEqual(uploadCount, 1, "same token within TTL must not re-dispatch")
        XCTAssertEqual(stamp, first, "and must not re-stamp")
    }

    func testUnchangedTokenAfterTTLReuploads() {
        HightouchPush.register(token: tokenA)
        XCTAssertEqual(uploadCount, 1)
        // Simulate the last upload being far in the past (well beyond the clamped minimum).
        UserDefaults.standard.set(1.0, forKey: lastUploadKey)

        HightouchPush.register(token: tokenA)

        XCTAssertEqual(uploadCount, 2, "same token past the TTL should re-dispatch (heartbeat)")
        XCTAssertGreaterThan(stamp, 1.0, "and re-stamp to now")
    }

    func testChangedTokenAlwaysUploadsWithinTTL() {
        HightouchPush.register(token: tokenA)
        XCTAssertEqual(uploadCount, 1)

        HightouchPush.register(token: tokenB)

        XCTAssertEqual(uploadCount, 2, "a rotated token must dispatch even within the TTL")
    }

    #if os(iOS) || targetEnvironment(macCatalyst)
    func testIdentifyForcesUploadWithinTTL() {
        HightouchPush.register(token: tokenA)
        XCTAssertEqual(uploadCount, 1)

        // identify() sets the one-shot bypass; simulate the OS re-firing didRegister with the same
        // token inside the TTL window — it must still dispatch to re-associate the token.
        HightouchPush.identify(userId: "reg-integration-user")
        HightouchPush.register(token: tokenA)

        XCTAssertEqual(uploadCount, 2, "identify() must force a re-dispatch despite the TTL window")
    }
    #endif
}
