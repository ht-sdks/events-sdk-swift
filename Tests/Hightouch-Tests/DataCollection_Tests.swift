import XCTest
@testable @_spi(HightouchInternal) import Hightouch

final class DataCollection_Tests: XCTestCase {

    private var createdAnalytics: [Analytics] = []

    override func tearDown() {
        // The stored choice lives in UserDefaults, so it would leak into the next run.
        for analytics in createdAnalytics {
            analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        }
        createdAnalytics = []
        super.tearDown()
    }

    /// A second call within one test stands in for an app restart: same write key, same storage.
    private func makeAnalytics(enabledByDefault: Bool = true) -> (Analytics, OutputReaderPlugin) {
        let configuration = Configuration(writeKey: "\(name)-data-collection")
            .trackApplicationLifecycleEvents(false)
            .dataCollectionEnabledByDefault(enabledByDefault)
        let analytics = Analytics(configuration: configuration)
        let output = OutputReaderPlugin()
        analytics.add(plugin: output)
        waitUntilStarted(analytics: analytics)
        createdAnalytics.append(analytics)
        return (analytics, output)
    }

    private func trackNames(_ output: OutputReaderPlugin) -> [String] {
        output.events.compactMap { ($0 as? TrackEvent)?.event }
    }

    func testCollectionIsOnByDefaultAndEventsAreProcessed() {
        let (analytics, output) = makeAnalytics()

        analytics.track(name: "collected")

        XCTAssertTrue(analytics.dataCollectionEnabled)
        XCTAssertEqual(trackNames(output), ["collected"])
    }

    func testDefaultOfOffDropsEveryEventTypeFromConstruction() {
        let (analytics, output) = makeAnalytics(enabledByDefault: false)

        analytics.track(name: "dropped")
        analytics.identify(userId: "user-1")
        analytics.screen(title: "Home")

        XCTAssertFalse(analytics.dataCollectionEnabled)
        XCTAssertNil(output.lastEvent)
    }

    func testDecisionIsMadeWhenTheEventIsTracked() {
        let (analytics, output) = makeAnalytics()

        analytics.track(name: "before off")
        analytics.dataCollectionEnabled = false
        analytics.track(name: "while off")
        analytics.dataCollectionEnabled = true
        analytics.track(name: "after on")

        XCTAssertEqual(trackNames(output), ["before off", "after on"])
    }

    func testReplayedRawEventsAreDroppedWhileOff() {
        let (analytics, output) = makeAnalytics(enabledByDefault: false)

        analytics.process(event: TrackEvent(event: "replayed", properties: nil))

        XCTAssertTrue(output.events.isEmpty)
    }

    func testUserIdentifiedWhileOffIsOnEventsAfterTurningOn() {
        let (analytics, output) = makeAnalytics()
        analytics.identify(userId: "user-1")

        analytics.dataCollectionEnabled = false
        analytics.identify(userId: "user-2")
        XCTAssertEqual(analytics.userId, "user-2")
        analytics.dataCollectionEnabled = true
        analytics.track(name: "after on")

        let tracked = output.events.compactMap { $0 as? TrackEvent }
        XCTAssertEqual(tracked.count, 1)
        XCTAssertEqual(tracked.first?.userId, "user-2")
    }

    func testStoredOffChoiceWinsOverDefaultOfOnAfterRestart() {
        let (first, _) = makeAnalytics()
        first.dataCollectionEnabled = false

        let (restarted, output) = makeAnalytics(enabledByDefault: true)
        restarted.track(name: "dropped")

        XCTAssertFalse(restarted.dataCollectionEnabled)
        XCTAssertTrue(output.events.isEmpty)
    }

    func testStoredOnChoiceWinsOverDefaultOfOffAfterRestart() {
        let (first, _) = makeAnalytics(enabledByDefault: false)
        first.dataCollectionEnabled = true

        let (restarted, output) = makeAnalytics(enabledByDefault: false)
        restarted.track(name: "collected")

        XCTAssertTrue(restarted.dataCollectionEnabled)
        XCTAssertEqual(trackNames(output), ["collected"])
    }

    func testKillSwitchStillDropsEventsWhileCollectionIsOn() {
        let (analytics, output) = makeAnalytics()

        analytics.enabled = false
        analytics.track(name: "dropped")

        XCTAssertTrue(output.events.isEmpty)
    }

    func testEventsTrackedBeforeTurningOffRemainQueuedForUpload() {
        let (analytics, _) = makeAnalytics()

        analytics.track(name: "before off")
        analytics.dataCollectionEnabled = false
        analytics.track(name: "while off")

        XCTAssertTrue(analytics.hasUnsentEvents)
    }

    private func trackTokenEvent(_ analytics: Analytics, type: String) {
        analytics.track(
            name: DeviceDeletionRequest.eventName,
            properties: [DeviceDeletionRequest.eventTypeProperty: type]
        )
    }

    private func tokenEventTypes(_ output: OutputReaderPlugin) -> [String] {
        output.events.compactMap {
            ($0 as? TrackEvent)?.properties?.dictionaryValue?[DeviceDeletionRequest.eventTypeProperty] as? String
        }
    }

    func testDeviceDeletionRequestIsTheOnlyEventDeliveredWhileOff() {
        let (analytics, output) = makeAnalytics(enabledByDefault: false)

        trackTokenEvent(analytics, type: "registered")
        trackTokenEvent(analytics, type: "disabled")
        analytics.track(name: "deleted")
        trackTokenEvent(analytics, type: DeviceDeletionRequest.eventType)

        XCTAssertEqual(tokenEventTypes(output), ["deleted"])
        XCTAssertEqual(output.events.count, 1)
    }

    func testDeviceDeletionRequestHeldAtStartupIsDeliveredWithCollectionOff() throws {
        let (analytics, output) = makeAnalytics(enabledByDefault: false)
        let startupQueue = try XCTUnwrap(analytics.find(pluginType: StartupQueue.self))
        let system: System = try XCTUnwrap(analytics.store.currentState())

        startupQueue.running = false
        trackTokenEvent(analytics, type: DeviceDeletionRequest.eventType)
        XCTAssertTrue(output.events.isEmpty)

        startupQueue.runningUpdate(state: system)

        XCTAssertEqual(tokenEventTypes(output), ["deleted"])
    }

    func testEventHeldAtStartupIsDroppedWhenCollectionGoesOffBeforeStartupFinishes() throws {
        let (analytics, output) = makeAnalytics()
        let startupQueue = try XCTUnwrap(analytics.find(pluginType: StartupQueue.self))
        let system: System = try XCTUnwrap(analytics.store.currentState())

        startupQueue.running = false
        analytics.track(name: "held at startup")
        analytics.dataCollectionEnabled = false

        startupQueue.runningUpdate(state: system)

        XCTAssertTrue(output.events.isEmpty)
    }

    func testKillSwitchDropsDeviceDeletionRequest() {
        let (analytics, output) = makeAnalytics()

        analytics.enabled = false
        trackTokenEvent(analytics, type: DeviceDeletionRequest.eventType)

        XCTAssertTrue(output.events.isEmpty)
    }
}
