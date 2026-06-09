//
//  Session_Tests.swift
//
//
//  Created by Cursor on 6/9/26.
//

import XCTest
import Sovran
@testable import Hightouch

final class Session_Tests: XCTestCase {
    func testAddsSessionContextToEveryEvent() {
        let analytics = makeAnalytics(writeKey: "session-context")
        let output = OutputReaderPlugin()
        analytics.add(plugin: output)
        let plugin = configuredSessionPlugin(from: analytics)

        plugin.now = { 1000 }
        waitUntilStarted(analytics: analytics)
        analytics.track(name: "First Event")

        plugin.now = { 1500 }
        analytics.track(name: "Second Event")

        let firstContext = context(at: 0, output: output)
        let firstSession = firstContext["session"] as? [String: Any]
        XCTAssertEqual(number(firstContext["sessionId"]), 1000)
        XCTAssertEqual(firstContext["sessionStart"] as? Bool, true)
        XCTAssertEqual(number(firstSession?["sessionId"]), 1000)
        XCTAssertEqual(number(firstSession?["sessionIndex"]), 0)
        XCTAssertEqual(firstSession?["sessionStart"] as? Bool, true)
        XCTAssertEqual(number(firstSession?["eventIndex"]), 0)
        XCTAssertTrue(firstSession?["previousSessionId"] is NSNull)
        XCTAssertEqual(firstSession?["firstEventId"] as? String, (output.events[0] as? TrackEvent)?.messageId)
        XCTAssertEqual(firstSession?["firstEventTimestamp"] as? String, (output.events[0] as? TrackEvent)?.timestamp)

        let secondContext = context(at: 1, output: output)
        let secondSession = secondContext["session"] as? [String: Any]
        XCTAssertEqual(number(secondContext["sessionId"]), 1000)
        XCTAssertNil(secondContext["sessionStart"])
        XCTAssertEqual(number(secondSession?["eventIndex"]), 1)
        XCTAssertNil(secondSession?["sessionStart"])
    }

    func testRotatesAfterForegroundInactivity() {
        let analytics = makeAnalytics(writeKey: "session-foreground-rotation")
        let output = OutputReaderPlugin()
        analytics.add(plugin: output)
        let plugin = configuredSessionPlugin(from: analytics)

        plugin.now = { 1000 }
        waitUntilStarted(analytics: analytics)
        analytics.track(name: "First Event")

        plugin.now = { 3001 }
        analytics.track(name: "Rotated Event")

        let eventContext = context(at: 1, output: output)
        let session = eventContext["session"] as? [String: Any]
        XCTAssertEqual(number(eventContext["sessionId"]), 3001)
        XCTAssertEqual(eventContext["sessionStart"] as? Bool, true)
        XCTAssertEqual(number(session?["sessionId"]), 3001)
        XCTAssertEqual(number(session?["sessionIndex"]), 1)
        XCTAssertEqual(number(session?["previousSessionId"]), 1000)
        XCTAssertEqual(number(session?["eventIndex"]), 0)
    }

    func testRotatesWhenResetIsCalled() {
        let analytics = makeAnalytics(writeKey: "session-reset")
        let output = OutputReaderPlugin()
        analytics.add(plugin: output)
        let plugin = configuredSessionPlugin(from: analytics)

        plugin.now = { 1000 }
        waitUntilStarted(analytics: analytics)
        analytics.track(name: "First Event")

        plugin.now = { 5000 }
        analytics.reset()
        analytics.track(name: "After Reset")

        let eventContext = context(at: 1, output: output)
        let session = eventContext["session"] as? [String: Any]
        XCTAssertEqual(number(session?["sessionId"]), 5000)
        XCTAssertEqual(number(session?["sessionIndex"]), 1)
        XCTAssertEqual(session?["sessionStart"] as? Bool, true)
        XCTAssertEqual(number(session?["previousSessionId"]), 1000)
        XCTAssertEqual(session?["firstEventId"] as? String, (output.events[0] as? TrackEvent)?.messageId)
    }

    func testDoesNotEnrichWhenBothTimeoutsAreZero() {
        let writeKey = "session-disabled"
        let storage = Storage(store: Store(), writeKey: writeKey)
        storage.hardReset(doYouKnowHowToUseThis: true)

        let analytics = Analytics(configuration: Configuration(writeKey: writeKey)
            .autoAddSegmentDestination(false)
            .trackApplicationLifecycleEvents(false)
            .foregroundSessionTimeout(0)
            .backgroundSessionTimeout(0))
        let output = OutputReaderPlugin()
        analytics.add(plugin: output)

        waitUntilStarted(analytics: analytics)
        analytics.track(name: "No Session Event")

        XCTAssertNil(analytics.find(pluginType: SessionPlugin.self))
        XCTAssertNil((output.lastEvent as? TrackEvent)?.context?.dictionaryValue?["session"])
        XCTAssertNil((output.lastEvent as? TrackEvent)?.context?.dictionaryValue?["sessionId"])
    }

    func testPersistsSessionStateAcrossAnalyticsInstances() {
        let writeKey = "session-persistence"
        resetStorage(writeKey: writeKey)

        var analytics: Analytics? = Analytics(configuration: Configuration(writeKey: writeKey)
            .autoAddSegmentDestination(false)
            .trackApplicationLifecycleEvents(false)
            .foregroundSessionTimeout(2000)
            .backgroundSessionTimeout(2000))
        var output = OutputReaderPlugin()
        analytics?.add(plugin: output)
        var plugin = configuredSessionPlugin(from: analytics!)

        plugin.now = { 1000 }
        waitUntilStarted(analytics: analytics)
        analytics?.track(name: "First Event")

        analytics = nil

        let nextAnalytics = Analytics(configuration: Configuration(writeKey: writeKey)
            .autoAddSegmentDestination(false)
            .trackApplicationLifecycleEvents(false)
            .foregroundSessionTimeout(2000)
            .backgroundSessionTimeout(2000))
        output = OutputReaderPlugin()
        nextAnalytics.add(plugin: output)
        plugin = configuredSessionPlugin(from: nextAnalytics)
        plugin.now = { 1500 }
        waitUntilStarted(analytics: nextAnalytics)
        nextAnalytics.track(name: "Second Event")

        let eventContext = context(at: 0, output: output)
        let session = eventContext["session"] as? [String: Any]
        XCTAssertEqual(number(session?["sessionId"]), 1000)
        XCTAssertEqual(number(session?["sessionIndex"]), 0)
        XCTAssertEqual(number(session?["eventIndex"]), 1)
        XCTAssertNil(session?["sessionStart"])
    }

    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
    func testRotatesAfterBackgroundTimeout() {
        let analytics = makeAnalytics(writeKey: "session-background-rotation")
        let output = OutputReaderPlugin()
        analytics.add(plugin: output)
        let plugin = configuredSessionPlugin(from: analytics)

        plugin.now = { 1000 }
        waitUntilStarted(analytics: analytics)
        analytics.track(name: "First Event")

        plugin.now = { 1500 }
        plugin.applicationWillResignActive(application: nil)

        plugin.now = { 4000 }
        plugin.applicationDidBecomeActive(application: nil)
        analytics.track(name: "Foreground Event")

        let eventContext = context(at: 1, output: output)
        let session = eventContext["session"] as? [String: Any]
        XCTAssertEqual(number(session?["sessionId"]), 4000)
        XCTAssertEqual(number(session?["sessionIndex"]), 1)
        XCTAssertEqual(number(session?["previousSessionId"]), 1000)
        XCTAssertEqual(session?["sessionStart"] as? Bool, true)
    }

    func testPreservesBackgroundTimestampWhenEventsAreProcessedWhileBackgrounded() {
        let analytics = makeAnalytics(writeKey: "session-background-event")
        let output = OutputReaderPlugin()
        analytics.add(plugin: output)
        let plugin = configuredSessionPlugin(from: analytics)

        plugin.now = { 1000 }
        waitUntilStarted(analytics: analytics)
        analytics.track(name: "First Event")

        plugin.now = { 1500 }
        plugin.applicationWillResignActive(application: nil)

        plugin.now = { 1501 }
        analytics.track(name: "Application Backgrounded")

        plugin.now = { 4000 }
        plugin.applicationDidBecomeActive(application: nil)
        analytics.track(name: "Foreground Event")

        let eventContext = context(at: 2, output: output)
        let session = eventContext["session"] as? [String: Any]
        XCTAssertEqual(number(session?["sessionId"]), 4000)
        XCTAssertEqual(number(session?["sessionIndex"]), 1)
        XCTAssertEqual(session?["sessionStart"] as? Bool, true)
        XCTAssertEqual(number(session?["eventIndex"]), 0)
        XCTAssertEqual(number(session?["previousSessionId"]), 1000)
    }
    #endif

    #if os(macOS)
    func testRotatesAfterBackgroundTimeout() {
        let analytics = makeAnalytics(writeKey: "session-background-rotation")
        let output = OutputReaderPlugin()
        analytics.add(plugin: output)
        let plugin = configuredSessionPlugin(from: analytics)

        plugin.now = { 1000 }
        waitUntilStarted(analytics: analytics)
        analytics.track(name: "First Event")

        plugin.now = { 1500 }
        plugin.applicationDidResignActive()

        plugin.now = { 4000 }
        plugin.applicationDidBecomeActive()
        analytics.track(name: "Foreground Event")

        let eventContext = context(at: 1, output: output)
        let session = eventContext["session"] as? [String: Any]
        XCTAssertEqual(number(session?["sessionId"]), 4000)
        XCTAssertEqual(number(session?["sessionIndex"]), 1)
        XCTAssertEqual(number(session?["previousSessionId"]), 1000)
        XCTAssertEqual(session?["sessionStart"] as? Bool, true)
    }

    func testPreservesBackgroundTimestampWhenEventsAreProcessedWhileBackgrounded() {
        let analytics = makeAnalytics(writeKey: "session-background-event")
        let output = OutputReaderPlugin()
        analytics.add(plugin: output)
        let plugin = configuredSessionPlugin(from: analytics)

        plugin.now = { 1000 }
        waitUntilStarted(analytics: analytics)
        analytics.track(name: "First Event")

        plugin.now = { 1500 }
        plugin.applicationDidResignActive()

        plugin.now = { 1501 }
        analytics.track(name: "Application Backgrounded")

        plugin.now = { 4000 }
        plugin.applicationDidBecomeActive()
        analytics.track(name: "Foreground Event")

        let eventContext = context(at: 2, output: output)
        let session = eventContext["session"] as? [String: Any]
        XCTAssertEqual(number(session?["sessionId"]), 4000)
        XCTAssertEqual(number(session?["sessionIndex"]), 1)
        XCTAssertEqual(session?["sessionStart"] as? Bool, true)
        XCTAssertEqual(number(session?["eventIndex"]), 0)
        XCTAssertEqual(number(session?["previousSessionId"]), 1000)
    }
    #endif

    private func makeAnalytics(writeKey suffix: String) -> Analytics {
        let writeKey = "test-\(suffix)"
        resetStorage(writeKey: writeKey)
        let analytics = Analytics(configuration: Configuration(writeKey: writeKey)
            .autoAddSegmentDestination(false)
            .trackApplicationLifecycleEvents(false)
            .foregroundSessionTimeout(2000)
            .backgroundSessionTimeout(2000))
        return analytics
    }

    private func resetStorage(writeKey: String) {
        let storage = Storage(store: Store(), writeKey: writeKey)
        storage.hardReset(doYouKnowHowToUseThis: true)
    }

    private func configuredSessionPlugin(from analytics: Analytics) -> SessionPlugin {
        guard let plugin = analytics.find(pluginType: SessionPlugin.self) else {
            XCTFail("Expected SessionPlugin to be registered")
            return SessionPlugin()
        }
        return plugin
    }

    private func context(at index: Int, output: OutputReaderPlugin) -> [String: Any] {
        guard output.events.indices.contains(index),
              let context = output.events[index].context?.dictionaryValue else {
            XCTFail("Expected event context at index \(index)")
            return [:]
        }
        return context
    }

    private func number(_ value: Any?) -> Int64? {
        switch value {
        case let value as Int64:
            return value
        case let value as Int:
            return Int64(value)
        case let value as NSNumber:
            return value.int64Value
        case let value as Decimal:
            return NSDecimalNumber(decimal: value).int64Value
        default:
            return nil
        }
    }
}

