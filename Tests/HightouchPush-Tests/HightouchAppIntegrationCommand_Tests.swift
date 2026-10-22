#if os(iOS) || targetEnvironment(macCatalyst)
import XCTest
@testable import Hightouch
@testable import HightouchPush
import UIKit

// A short injected deadline races a slow sync; the real 20s deadline would make this test too slow.
final class HightouchAppIntegrationCommand_Tests: XCTestCase {

    private final class FakeSilentPushDelegate: HightouchSilentPushDelegate {
        private(set) var receiveCallCount = 0
        private(set) var lastCustomData: [String: String]?

        func receive(customData: [String: String]) async {
            receiveCallCount += 1
            lastCustomData = customData
        }
    }

    private var silentPushDelegate: FakeSilentPushDelegate!

    override func setUp() {
        super.setUp()
        silentPushDelegate = FakeSilentPushDelegate()
        HightouchMessages.resetForTesting()
    }

    override func tearDown() {
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-appintegration-teardown"),
            config: HightouchPushConfig(appId: "appintegration-teardown")
        )
        HightouchMessages.resetForTesting()
        silentPushDelegate = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func initialize(includeSilentPushDelegate: Bool = true) {
        var config = HightouchPushConfig(appId: "appintegration-test-app")
        if includeSilentPushDelegate {
            config.silentPushDelegate = silentPushDelegate
        }
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "\(name)-appintegration"),
            config: config
        )
    }

    private func hightouchUserInfo(
        messageId: String? = "push-msg-1",
        command: [String: Any]? = nil,
        customData: [String: String]? = nil
    ) -> [AnyHashable: Any] {
        var hightouch: [String: Any] = [:]
        if let messageId = messageId { hightouch["messageId"] = messageId }
        if let command = command { hightouch["command"] = command }
        if let customData = customData { hightouch["customData"] = customData }
        return [
            "aps": ["content-available": 1],
            "hightouch": hightouch,
        ]
    }

    @discardableResult
    private func driveApplication(_ userInfo: [AnyHashable: Any]) -> [UIBackgroundFetchResult] {
        var results: [UIBackgroundFetchResult] = []
        let completed = expectation(description: "fetch completion")
        HightouchAppIntegration.application(
            UIApplication.shared,
            didReceiveRemoteNotification: userInfo,
            fetchCompletionHandler: { result in
                results.append(result)
                completed.fulfill()
            }
        )
        wait(for: [completed], timeout: 5)
        return results
    }

    // MARK: - Regression: the pre-existing customData path is untouched

    func testCustomDataPushStillReachesSilentPushDelegateAndCompletesNewData() {
        initialize()

        let results = driveApplication(hightouchUserInfo(customData: ["foo": "bar"]))

        XCTAssertEqual(results, [.newData])
        XCTAssertEqual(silentPushDelegate.receiveCallCount, 1)
        XCTAssertEqual(silentPushDelegate.lastCustomData, ["foo": "bar"])
    }

    func testCustomDataPushWithNoDelegateCompletesNoData() {
        initialize(includeSilentPushDelegate: false)

        let results = driveApplication(hightouchUserInfo(customData: ["foo": "bar"]))

        XCTAssertEqual(results, [.noData])
    }

    func testNonHightouchPushCompletesNoData() {
        initialize()

        let completed = expectation(description: "fetch completion")
        var captured: UIBackgroundFetchResult?
        HightouchAppIntegration.application(
            UIApplication.shared,
            didReceiveRemoteNotification: ["aps": ["alert": "hi"]],
            fetchCompletionHandler: { result in
                captured = result
                completed.fulfill()
            }
        )
        wait(for: [completed], timeout: 5)

        XCTAssertEqual(captured, .noData)
    }

    // MARK: - The bug this phase fixes

    func testCommandPushWithNoCustomDataIsNoLongerDropped() {
        initialize()
        let output = OutputReaderPlugin()
        HightouchPush.analytics.add(plugin: output)
        waitUntilStarted(analytics: HightouchPush.analytics)

        let userInfo = hightouchUserInfo(messageId: nil, command: ["verb": "syncMessages"])
        let results = driveApplication(userInfo)

        XCTAssertEqual(results, [.noData], "messages isn't configured in this test, so the real sync no-ops")

        let delivered = output.events.compactMap { $0 as? TrackEvent }.filter {
            $0.event == "CEP Engagement Events" && $0.properties?["provider_event_type"]?.stringValue == "delivered"
        }
        XCTAssertEqual(delivered.count, 1, "the command must actually be handled, not dropped")
        XCTAssertEqual(delivered.first?.properties?["sync_reason"]?.stringValue, "syncMessages")
    }

    // MARK: - Exactly-once completion

    func testCompletionFiresExactlyOnceForACommandPush() {
        initialize()

        let userInfo = hightouchUserInfo(command: ["verb": "syncMessages"])
        let results = driveApplication(userInfo)

        XCTAssertEqual(results.count, 1)
    }

    func testCompletionFiresExactlyOnceWhenDeadlineRacesASlowSync() {
        initialize()

        let userInfo = hightouchUserInfo(command: ["verb": "syncMessages"])
        var results: [UIBackgroundFetchResult] = []
        let lock = NSLock()
        let deadlineFired = expectation(description: "deadline-driven completion")
        let slowSyncReturned = expectation(description: "slow sync eventually returns")

        HightouchMessagesTrigger.handle(
            userInfo: userInfo,
            completionHandler: { result in
                lock.lock(); results.append(result); lock.unlock()
                deadlineFired.fulfill()
            },
            isInitialized: true,
            deadline: 0.05,
            sync: { _ in
                try? await Task.sleep(nanoseconds: 300_000_000)
                slowSyncReturned.fulfill()
                return .changed(messageCount: 1)
            }
        )

        wait(for: [deadlineFired], timeout: 2)
        wait(for: [slowSyncReturned], timeout: 2)

        lock.lock()
        let finalResults = results
        lock.unlock()
        XCTAssertEqual(finalResults, [.failed], "the deadline must win the race, and only once")
    }

    /// Built independently of MessagesISO8601 so the test isn't checking the implementation against itself.

    func testCommandAndCustomDataAreBothHandledWithOneCompletion() {
        initialize()

        let userInfo = hightouchUserInfo(command: ["verb": "syncMessages"], customData: ["foo": "bar"])
        let results = driveApplication(userInfo)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(silentPushDelegate.receiveCallCount, 1, "customData must still reach the delegate")
        XCTAssertEqual(silentPushDelegate.lastCustomData, ["foo": "bar"])
    }

    // MARK: - Sync failure

    func testFailedWhenSyncFails() {
        initialize()

        let userInfo = hightouchUserInfo(command: ["verb": "syncMessages"])
        let completed = expectation(description: "fetch completion")
        var captured: UIBackgroundFetchResult?

        HightouchMessagesTrigger.handle(
            userInfo: userInfo,
            completionHandler: { result in
                captured = result
                completed.fulfill()
            },
            isInitialized: true,
            sync: { _ in .failed(URLError(.timedOut)) }
        )

        wait(for: [completed], timeout: 5)
        XCTAssertEqual(captured, .failed)
    }

    // MARK: - Not initialized

    func testNoDataWhenNotInitialized() {
        let userInfo = hightouchUserInfo(command: ["verb": "syncMessages"])
        let completed = expectation(description: "fetch completion")
        var captured: UIBackgroundFetchResult?
        var syncWasCalled = false

        HightouchMessagesTrigger.handle(
            userInfo: userInfo,
            completionHandler: { result in
                captured = result
                completed.fulfill()
            },
            isInitialized: false,
            sync: { _ in
                syncWasCalled = true
                return .changed(messageCount: 1)
            }
        )

        wait(for: [completed], timeout: 5)
        XCTAssertEqual(captured, .noData)
        XCTAssertFalse(syncWasCalled, "a push that arrived before initialize() must not attempt any work")
    }

    // MARK: - Forward compatibility

    func testUnknownVerbFallsThroughToLegacyPath() {
        initialize()

        let userInfo = hightouchUserInfo(messageId: "push-msg-2", command: ["verb": "someFutureVerb"])
        let results = driveApplication(userInfo)

        XCTAssertEqual(results, [.noData])
        XCTAssertEqual(silentPushDelegate.receiveCallCount, 0)
    }
}
#endif
