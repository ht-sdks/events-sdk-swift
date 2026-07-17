import XCTest
import Hightouch
@testable import HightouchPush

/// On-device (simulator) integration tests that drive the real `HightouchPush.register(token:)`
/// against real `UserDefaults`, verifying the dedupe + TTL-heartbeat gating.
///
/// The gate is observed via the persisted `com.hightouch.push.lastTokenUploadAt` timestamp, which
/// `register(token:)` writes *only* when it actually uploads (fires the "registered" event). A
/// changed timestamp therefore means "uploaded"; an unchanged one means "deduped". This mirrors the
/// Android emulator verification, which reads `last_uploaded_at_millis` from SharedPreferences.
final class HightouchPushRegisterIntegration_Tests: XCTestCase {

    private let lastUploadKey = "com.hightouch.push.lastTokenUploadAt"
    private let apnsKey = "com.hightouch.push.apnsToken"
    private let tokenA = Data([0x01, 0x02, 0x03, 0x04])
    private let tokenB = Data([0x0a, 0x0b, 0x0c, 0x0d])

    override func setUp() {
        super.setUp()
        // Clean slate: no cached token, never-uploaded. Then initialize so the SDK reloads state
        // from the cleared defaults (resets in-memory _apnsToken / _currentUserId).
        UserDefaults.standard.removeObject(forKey: lastUploadKey)
        UserDefaults.standard.removeObject(forKey: apnsKey)
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-reg-integration"),
            config: HightouchPushConfig(appId: "reg-integration-app")
        )
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: lastUploadKey)
        UserDefaults.standard.removeObject(forKey: apnsKey)
        super.tearDown()
    }

    private var stamp: Double { UserDefaults.standard.double(forKey: lastUploadKey) }

    func testFirstRegisterUploadsAndStamps() {
        XCTAssertEqual(stamp, 0, "precondition: never uploaded")
        HightouchPush.register(token: tokenA)
        XCTAssertGreaterThan(stamp, 0, "first register should upload and stamp")
    }

    func testUnchangedTokenWithinTTLIsDeduped() {
        HightouchPush.register(token: tokenA)
        let first = stamp
        XCTAssertGreaterThan(first, 0)

        HightouchPush.register(token: tokenA)
        XCTAssertEqual(stamp, first, "same token within TTL must be deduped (no re-stamp)")
    }

    func testUnchangedTokenAfterTTLReuploads() {
        HightouchPush.register(token: tokenA)
        // Simulate the last upload being far in the past (well beyond the clamped minimum).
        UserDefaults.standard.set(1.0, forKey: lastUploadKey)

        HightouchPush.register(token: tokenA)
        XCTAssertGreaterThan(stamp, 1.0, "same token past the TTL should re-upload (heartbeat)")
    }

    func testChangedTokenAlwaysUploadsWithinTTL() {
        HightouchPush.register(token: tokenA)
        let first = stamp

        HightouchPush.register(token: tokenB)
        XCTAssertNotEqual(stamp, first, "a rotated token must upload even within the TTL")
    }

    #if os(iOS) || targetEnvironment(macCatalyst)
    func testIdentifyForcesUploadWithinTTL() {
        HightouchPush.register(token: tokenA)
        let first = stamp
        XCTAssertGreaterThan(first, 0)

        // identify() sets the one-shot bypass and asks the OS to re-fire didRegister. Simulate that
        // OS callback with the same token inside the TTL window: it must still upload so the token
        // is re-associated with the new user.
        HightouchPush.identify(userId: "reg-integration-user")
        HightouchPush.register(token: tokenA)
        XCTAssertGreaterThan(stamp, first, "identify() must force a re-upload despite the TTL window")

        HightouchPush.logout()
    }
    #endif
}
