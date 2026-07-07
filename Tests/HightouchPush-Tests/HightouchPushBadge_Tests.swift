#if os(iOS) || targetEnvironment(macCatalyst)
import XCTest
import Hightouch
@testable import HightouchPush

final class HightouchPushBadge_Tests: XCTestCase {

    private func initialize(writeKey: String, config: HightouchPushConfig) {
        HightouchPush.initialize(
            configuration: Configuration(writeKey: writeKey),
            config: config
        )
    }

    override func tearDown() {
        let baseline = HightouchPushConfig(appId: "test-badge-teardown")
        initialize(writeKey: "test-badge-teardown", config: baseline)
        super.tearDown()
    }

    func testClampedBadgeCountLeavesPositiveValuesUnchanged() {
        XCTAssertEqual(HightouchPush.clampedBadgeCount(7), 7)
    }

    func testClampedBadgeCountClampsNegativeValuesToZero() {
        XCTAssertEqual(HightouchPush.clampedBadgeCount(-3), 0)
    }

    // MARK: - autoClearBadgeOnForeground

    func testAutoClearBadgeOnForegroundDefaultIsFalse() {
        let config = HightouchPushConfig(appId: "test-default")
        XCTAssertFalse(config.autoClearBadgeOnForeground)
    }

    func testInitializeWithAutoClearBadgeOnForegroundTrueRegistersObserver() {
        var config = HightouchPushConfig(appId: "test-foreground-on")
        config.autoClearBadgeOnForeground = true
        initialize(writeKey: "test-foreground-on", config: config)

        XCTAssertTrue(HightouchPush.isForegroundBadgeResetObserverRegistered)
    }

    func testInitializeWithAutoClearBadgeOnForegroundFalseDoesNotRegisterObserver() {
        var config = HightouchPushConfig(appId: "test-foreground-off")
        config.autoClearBadgeOnForeground = false
        initialize(writeKey: "test-foreground-off", config: config)

        XCTAssertFalse(HightouchPush.isForegroundBadgeResetObserverRegistered)
    }

    func testReinitializeWithFlagOffRemovesPriorObserver() {
        var on = HightouchPushConfig(appId: "test-reinit-on")
        on.autoClearBadgeOnForeground = true
        initialize(writeKey: "test-reinit-on", config: on)
        XCTAssertTrue(HightouchPush.isForegroundBadgeResetObserverRegistered)

        var off = HightouchPushConfig(appId: "test-reinit-off")
        off.autoClearBadgeOnForeground = false
        initialize(writeKey: "test-reinit-off", config: off)

        XCTAssertFalse(HightouchPush.isForegroundBadgeResetObserverRegistered)
    }

    func testReinitializeWithFlagOnKeepsObserverRegistered() {
        var config = HightouchPushConfig(appId: "test-reinit-on-on")
        config.autoClearBadgeOnForeground = true
        initialize(writeKey: "test-reinit-on-on-1", config: config)
        initialize(writeKey: "test-reinit-on-on-2", config: config)

        XCTAssertTrue(HightouchPush.isForegroundBadgeResetObserverRegistered)
    }
}
#endif
