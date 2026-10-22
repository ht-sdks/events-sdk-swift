import XCTest
@testable import HightouchPush
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class HightouchMessagesSyncGate_Tests: XCTestCase {

    private let interval: TimeInterval = 15 * 60

    func testShouldSyncWhenNeverSyncedBefore() {
        XCTAssertTrue(MessagesSyncCoordinator.shouldSync(
            lastSyncedAt: 0,
            now: Date().timeIntervalSince1970,
            cooldown: interval,
            force: false
        ))
    }

    func testShouldNotSyncWithinCooldownWindow() {
        let now = interval * 10
        XCTAssertFalse(MessagesSyncCoordinator.shouldSync(
            lastSyncedAt: now - (interval - 1),
            now: now,
            cooldown: interval,
            force: false
        ))
    }

    func testShouldSyncAfterCooldownElapses() {
        let now = interval * 10
        XCTAssertTrue(MessagesSyncCoordinator.shouldSync(
            lastSyncedAt: now - interval,
            now: now,
            cooldown: interval,
            force: false
        ))
    }

    func testForceBypassesCooldownEvenImmediatelyAfterASync() {
        let now = interval * 10
        XCTAssertTrue(MessagesSyncCoordinator.shouldSync(
            lastSyncedAt: now,
            now: now,
            cooldown: interval,
            force: true
        ))
    }

    // MARK: - Minimum-cooldown clamp

    func testCooldownBelowTheMinimumIsClampedUpToIt() {
        let now: TimeInterval = 1_000_000
        XCTAssertFalse(MessagesSyncCoordinator.shouldSync(lastSyncedAt: now - 10, now: now, cooldown: 5, force: false))
        XCTAssertTrue(MessagesSyncCoordinator.shouldSync(
            lastSyncedAt: now - MessagesSyncCoordinator.minCooldown,
            now: now,
            cooldown: 5,
            force: false
        ))
    }
}

// MARK: - Foreground observer registration

#if os(iOS) || targetEnvironment(macCatalyst)

final class HightouchMessagesForegroundSync_Tests: XCTestCase {

    override func tearDown() {
        HightouchMessages.resetForTesting()
        super.tearDown()
    }

    private func initialize(writeKey: String, syncOnForeground: Bool) {
        var config = HightouchMessagesConfig()
        config.syncOnForeground = syncOnForeground
        HightouchMessages.testStoreLocation = .ephemeral
        HightouchMessages.initialize(analytics: Analytics(configuration: Configuration(writeKey: writeKey)), config: config)
    }

    func testInitializeWithSyncOnForegroundTrueRegistersObserver() {
        initialize(writeKey: "\(name)-on", syncOnForeground: true)
        XCTAssertTrue(HightouchMessages.isMessagesForegroundObserverRegistered)
    }

    func testInitializeWithSyncOnForegroundFalseDoesNotRegisterObserver() {
        initialize(writeKey: "\(name)-off", syncOnForeground: false)
        XCTAssertFalse(HightouchMessages.isMessagesForegroundObserverRegistered)
    }

    func testReinitializeWithFlagOffRemovesThePriorObserver() {
        initialize(writeKey: "\(name)-reinit-on", syncOnForeground: true)
        XCTAssertTrue(HightouchMessages.isMessagesForegroundObserverRegistered)

        initialize(writeKey: "\(name)-reinit-off", syncOnForeground: false)
        XCTAssertFalse(
            HightouchMessages.isMessagesForegroundObserverRegistered,
            "re-initializing with syncOnForeground: false must actually remove the observer"
        )
    }

    func testReinitializeWithFlagOnKeepsTheObserverRegistered() {
        initialize(writeKey: "\(name)-reinit-on-on-1", syncOnForeground: true)
        initialize(writeKey: "\(name)-reinit-on-on-2", syncOnForeground: true)
        XCTAssertTrue(HightouchMessages.isMessagesForegroundObserverRegistered)
    }
}

#endif
#endif
