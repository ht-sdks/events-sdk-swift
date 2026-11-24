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
    private let deletionSentKey = "com.hightouch.push.deletionSent"
    private let tokenA = Data([0x01, 0x02, 0x03, 0x04])
    private let tokenB = Data([0x0a, 0x0b, 0x0c, 0x0d])
    private var output: OutputReaderPlugin!

    override func setUp() {
        super.setUp()
        // Clean slate: no cached token, never-uploaded. Then initialize (unique write key for
        // storage isolation) so the SDK reloads state from the cleared defaults.
        UserDefaults.standard.removeObject(forKey: lastUploadKey)
        UserDefaults.standard.removeObject(forKey: apnsKey)
        UserDefaults.standard.removeObject(forKey: deletionSentKey)
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
        UserDefaults.standard.removeObject(forKey: deletionSentKey)
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

    // MARK: - Data collection switch

    private var lastUploadedTokenEvent: TrackEvent? {
        output.events.compactMap { $0 as? TrackEvent }
            .last { $0.event == "CEP Push Token Events" }
    }

    func testDataCollectionIsOnByDefault() {
        XCTAssertTrue(HightouchPush.isDataCollectionEnabled)
    }

    func testConfigurationDefaultOfOffStartsWithCollectionOff() {
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-reg-integration")
                .dataCollectionEnabledByDefault(false),
            config: HightouchPushConfig(appId: "reg-integration-app")
        )

        XCTAssertFalse(HightouchPush.isDataCollectionEnabled)
    }

    func testTurningCollectionOffSendsNothingAndKeepsTheUser() {
        HightouchPush.register(token: tokenA)
        HightouchPush.identify(userId: "reg-integration-user")
        let eventsBefore = output.events.count

        HightouchPush.setDataCollectionEnabled(false)

        XCTAssertFalse(HightouchPush.isDataCollectionEnabled)
        XCTAssertEqual(output.events.count, eventsBefore, "turning collection off must not send an event")
        XCTAssertEqual(HightouchPush.userId, "reg-integration-user")
    }

    func testTokenRegisteredWhileCollectionIsOffIsNotStampedAsUploaded() {
        HightouchPush.setDataCollectionEnabled(false)

        HightouchPush.register(token: tokenA)

        XCTAssertEqual(uploadCount, 0, "nothing may be dispatched while collection is off")
        XCTAssertEqual(stamp, 0, "and a dropped registration must not count as an upload")
        XCTAssertEqual(HightouchPush.deviceTokenHex, "01020304", "the token is still recorded locally")
    }

    func testTurningCollectionBackOnRegistersTheTokenForTheUserIdentifiedWhileOff() {
        HightouchPush.register(token: tokenA)
        XCTAssertEqual(uploadCount, 1)
        HightouchPush.setDataCollectionEnabled(false)
        HightouchPush.identify(userId: "reg-integration-user")

        HightouchPush.setDataCollectionEnabled(true)

        XCTAssertEqual(uploadCount, 2, "turning collection on must re-register despite the TTL window")
        XCTAssertEqual(lastUploadedTokenEvent?.userId, "reg-integration-user")
        XCTAssertEqual(lastUploadedTokenEvent?.properties?.dictionaryValue?["provider_event_type"] as? String, "registered")
        XCTAssertGreaterThan(stamp, 0)
    }

    func testTurningCollectionOnWhenAlreadyOnSendsNothing() {
        HightouchPush.register(token: tokenA)
        XCTAssertEqual(uploadCount, 1)

        HightouchPush.setDataCollectionEnabled(true)

        XCTAssertEqual(uploadCount, 1)
    }

    func testTurningCollectionOnWithoutATokenSendsNothing() {
        HightouchPush.setDataCollectionEnabled(false)

        HightouchPush.setDataCollectionEnabled(true)

        XCTAssertTrue(HightouchPush.isDataCollectionEnabled)
        XCTAssertEqual(uploadCount, 0)
    }

    func testDataCollectionChoicePersistsAcrossReinitialization() {
        HightouchPush.setDataCollectionEnabled(false)

        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-reg-integration")
                .dataCollectionEnabledByDefault(true),
            config: HightouchPushConfig(appId: "reg-integration-app")
        )

        XCTAssertFalse(HightouchPush.isDataCollectionEnabled)
    }

    func testLogoutWhileCollectionIsOffClearsUserLocallyAndReEnablingRegistersAnonymous() {
        HightouchPush.register(token: tokenA)
        HightouchPush.identify(userId: "reg-integration-user")
        let anonymousIdBefore = HightouchPush.anonymousId
        let eventsBefore = output.events.count
        HightouchPush.setDataCollectionEnabled(false)

        HightouchPush.logout()

        XCTAssertEqual(output.events.count, eventsBefore, "logout while off must not send a disabled event")
        XCTAssertNil(HightouchPush.userId)
        XCTAssertNotEqual(HightouchPush.anonymousId, anonymousIdBefore)

        HightouchPush.setDataCollectionEnabled(true)

        XCTAssertEqual(uploadCount, 2)
        XCTAssertEqual(lastUploadedTokenEvent?.properties?.dictionaryValue?["provider_event_type"] as? String, "registered")
        XCTAssertNil(lastUploadedTokenEvent?.userId)
    }

    func testTokenRegisteredWithKillSwitchOffIsNotStampedAsUploaded() {
        HightouchPush.analytics.enabled = false

        HightouchPush.register(token: tokenA)

        XCTAssertEqual(uploadCount, 0)
        XCTAssertEqual(stamp, 0)
    }

    // MARK: - wipeData

    private func tokenEvents(ofType providerEventType: String) -> [TrackEvent] {
        output.events.compactMap { $0 as? TrackEvent }
            .filter { $0.event == "CEP Push Token Events" }
            .filter { $0.properties?.dictionaryValue?["provider_event_type"] as? String == providerEventType }
    }

    func testWipeDataTurnsCollectionOffSendsOneDeletionForTheUserAndLogsOut() {
        HightouchPush.register(token: tokenA)
        HightouchPush.identify(userId: "reg-integration-user")
        let anonymousIdBefore = HightouchPush.anonymousId

        HightouchPush.wipeData()

        XCTAssertFalse(HightouchPush.isDataCollectionEnabled)
        let storedChoice: Bool? = HightouchPush.analytics.storage.read(.dataCollectionEnabled)
        XCTAssertEqual(storedChoice, false)

        let deletions = tokenEvents(ofType: "deleted")
        XCTAssertEqual(deletions.count, 1)
        let properties = deletions.first?.properties?.dictionaryValue
        XCTAssertEqual(properties?["token"] as? String, "01020304")
        XCTAssertEqual(properties?["device_id"] as? String, HightouchPush.deviceId)
        XCTAssertEqual(properties?["app_id"] as? String, "reg-integration-app")
        XCTAssertEqual(properties?["userId"] as? String, "reg-integration-user")
        XCTAssertEqual(deletions.first?.userId, "reg-integration-user", "attributed to the user being wiped")
        XCTAssertEqual(deletions.first?.anonymousId, anonymousIdBefore, "and to the anonymous id from before the reset")

        XCTAssertTrue(tokenEvents(ofType: "disabled").isEmpty)
        XCTAssertNil(HightouchPush.userId)
        XCTAssertNil(HightouchPush.analytics.userId)
        XCTAssertNotEqual(HightouchPush.anonymousId, anonymousIdBefore)
        XCTAssertEqual(stamp, 0, "the next registration must not be deduped")
        XCTAssertEqual(HightouchPush.deviceTokenHex, "01020304", "the token is kept")
    }

    func testWipeDataSendsTheDeletionWhenCollectionWasAlreadyOff() {
        HightouchPush.register(token: tokenA)
        HightouchPush.identify(userId: "reg-integration-user")
        HightouchPush.setDataCollectionEnabled(false)

        HightouchPush.wipeData()

        XCTAssertEqual(tokenEvents(ofType: "deleted").count, 1)
        XCTAssertEqual(tokenEvents(ofType: "deleted").first?.userId, "reg-integration-user")
        XCTAssertNil(HightouchPush.userId)
    }

    func testWipeDataSendsTheDeletionAndResetsAnAnonymousDevice() {
        HightouchPush.register(token: tokenA)
        let anonymousIdBefore = HightouchPush.anonymousId

        HightouchPush.wipeData()

        let deletions = tokenEvents(ofType: "deleted")
        XCTAssertEqual(deletions.count, 1)
        XCTAssertNil(deletions.first?.userId)
        XCTAssertNil(deletions.first?.properties?.dictionaryValue?["userId"])
        XCTAssertEqual(deletions.first?.anonymousId, anonymousIdBefore)
        XCTAssertNotEqual(HightouchPush.anonymousId, anonymousIdBefore)
    }

    func testWipeDataSendsTheDeletionWithoutATokenProperty() {
        HightouchPush.wipeData()

        let deletions = tokenEvents(ofType: "deleted")
        XCTAssertEqual(deletions.count, 1)
        let properties = deletions.first?.properties?.dictionaryValue
        XCTAssertNil(properties?["token"])
        XCTAssertEqual(properties?["device_id"] as? String, HightouchPush.deviceId)
    }

    func testSecondWipeDataSendsNothingMore() {
        HightouchPush.register(token: tokenA)
        HightouchPush.wipeData()
        let eventsAfterFirstWipe = output.events.count

        HightouchPush.wipeData()

        XCTAssertEqual(output.events.count, eventsAfterFirstWipe)
    }

    func testWipeDataSendsTheDeletionAgainAfterCollectionWasTurnedBackOn() {
        HightouchPush.register(token: tokenA)
        HightouchPush.wipeData()
        HightouchPush.setDataCollectionEnabled(true)

        HightouchPush.wipeData()

        XCTAssertEqual(tokenEvents(ofType: "deleted").count, 2)
    }

    func testWipeDataWithTheKillSwitchOffSendsNothingAndALaterCallSendsTheDeletion() {
        HightouchPush.register(token: tokenA)
        HightouchPush.identify(userId: "reg-integration-user")
        let eventsBefore = output.events.count

        HightouchPush.analytics.enabled = false
        HightouchPush.wipeData()

        XCTAssertEqual(output.events.count, eventsBefore)
        XCTAssertFalse(HightouchPush.isDataCollectionEnabled)
        XCTAssertNil(HightouchPush.userId)

        HightouchPush.analytics.enabled = true
        HightouchPush.wipeData()

        XCTAssertEqual(tokenEvents(ofType: "deleted").count, 1)
    }

    func testWipeDataKeepsTheDeviceId() {
        HightouchPush.register(token: tokenA)
        let deviceIdBefore = HightouchPush.deviceId

        HightouchPush.wipeData()

        XCTAssertEqual(HightouchPush.deviceId, deviceIdBefore)
        XCTAssertEqual(
            tokenEvents(ofType: "deleted").first?.properties?.dictionaryValue?["device_id"] as? String,
            deviceIdBefore
        )
    }

    func testTurningCollectionOnAfterWipeDataRegistersTheTokenWithNoUser() {
        HightouchPush.register(token: tokenA)
        HightouchPush.identify(userId: "reg-integration-user")
        HightouchPush.wipeData()
        let registrationsBefore = tokenEvents(ofType: "registered").count

        HightouchPush.setDataCollectionEnabled(true)

        let registrations = tokenEvents(ofType: "registered")
        XCTAssertEqual(registrations.count, registrationsBefore + 1)
        XCTAssertNil(registrations.last?.userId)
        XCTAssertEqual(registrations.last?.properties?.dictionaryValue?["token"] as? String, "01020304")
    }
}
