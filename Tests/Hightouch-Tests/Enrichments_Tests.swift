//
//  Enrichments_Tests.swift
//  Hightouch-Tests
//

import XCTest
@testable import Hightouch

final class Enrichments_Tests: XCTestCase {

    // Thread-safe output capture; OutputReaderPlugin only records track events
    // and isn't safe to append to from multiple threads.
    class CaptureAllPlugin: Plugin {
        let type: PluginType = .after
        var analytics: Analytics?

        private let lock = NSLock()
        private var _events = [RawEvent]()
        var events: [RawEvent] {
            lock.lock()
            defer { lock.unlock() }
            return _events
        }

        func execute<T: RawEvent>(event: T?) -> T? {
            if let event = event {
                lock.lock()
                _events.append(event)
                lock.unlock()
            }
            return event
        }
    }

    private func makeAnalytics(writeKey: String) -> (Analytics, CaptureAllPlugin) {
        UserDefaults.standard.removePersistentDomain(forName: "com.hightouch.storage.\(writeKey)")
        let analytics = Analytics(configuration: Configuration(writeKey: writeKey))
        let capture = CaptureAllPlugin()
        analytics.add(plugin: capture)
        waitUntilStarted(analytics: analytics)
        return (analytics, capture)
    }

    private func schemaVersionEnrichment(_ version: String) -> EnrichmentClosure {
        return { event in
            guard var workingEvent = event else { return event }
            var context = workingEvent.context?.dictionaryValue ?? [String: Any]()
            context["protocols"] = ["schemaVersion": version]
            workingEvent.context = try? JSON(context)
            return workingEvent
        }
    }

    private func schemaVersion(of event: RawEvent?) -> String? {
        return event?.context?.value(forKeyPath: KeyPath("protocols.schemaVersion"))
    }

    func testConcurrentAliasEnrichmentsDoNotSwapStamps() {
        let (analytics, capture) = makeAnalytics(writeKey: "enrichConcurrencyTest")

        // Each closure records the messageId of every event it runs on. If the
        // implementation leaked closures across overlapping calls (e.g. via a
        // shared plugin added/removed around each call), both closures would run
        // on the same event and the recorded sets would overlap, or an event's
        // final stamp would disagree with the closure that claimed it.
        let lock = NSLock()
        var touchedByA = Set<String>()
        var touchedByB = Set<String>()

        func recordingEnrichment(_ version: String, into touched: @escaping (String) -> Void) -> EnrichmentClosure {
            let stamp = schemaVersionEnrichment(version)
            return { event in
                if let messageId = event?.messageId {
                    lock.lock()
                    touched(messageId)
                    lock.unlock()
                }
                return stamp(event)
            }
        }

        let iterations = 50
        let group = DispatchGroup()
        let queueA = DispatchQueue(label: "enrichments.queueA")
        let queueB = DispatchQueue(label: "enrichments.queueB")

        queueA.async(group: group) {
            for i in 0..<iterations {
                analytics.alias(newId: "user-a-\(i)",
                                enrichments: [recordingEnrichment("schema-a", into: { touchedByA.insert($0) })])
            }
        }
        queueB.async(group: group) {
            for i in 0..<iterations {
                analytics.alias(newId: "user-b-\(i)",
                                enrichments: [recordingEnrichment("schema-b", into: { touchedByB.insert($0) })])
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)

        let aliasEvents = capture.events.compactMap { $0 as? AliasEvent }
        XCTAssertEqual(aliasEvents.count, iterations * 2)

        // each closure ran on exactly its own events, never on the other call's.
        XCTAssertEqual(touchedByA.count, iterations)
        XCTAssertEqual(touchedByB.count, iterations)
        XCTAssertTrue(touchedByA.isDisjoint(with: touchedByB),
                      "An enrichment closure ran on an event from an overlapping call.")

        for event in aliasEvents {
            guard let messageId = event.messageId else {
                XCTFail("Alias event is missing its messageId.")
                continue
            }
            let expected = touchedByA.contains(messageId) ? "schema-a" : "schema-b"
            XCTAssertEqual(self.schemaVersion(of: event), expected,
                           "Enrichment stamp was swapped between overlapping calls.")
        }
    }

    func testEnrichmentPreservesPlatformContext() {
        let (analytics, capture) = makeAnalytics(writeKey: "enrichContextTest")

        analytics.track(name: "enriched event", enrichments: [schemaVersionEnrichment("v1")])

        let event = capture.events.last as? TrackEvent
        XCTAssertNotNil(event)
        XCTAssertEqual(schemaVersion(of: event), "v1")

        // platform context stamped by the Context plugin must remain intact.
        let context = event?.context?.dictionaryValue
        XCTAssertNotNil(context?["library"])
        XCTAssertNotNil(context?["os"])
    }

    func testEventWithoutEnrichmentsHasNoProtocolsKey() {
        let (analytics, capture) = makeAnalytics(writeKey: "enrichNoLeakTest")

        analytics.track(name: "enriched event", enrichments: [schemaVersionEnrichment("v1")])
        analytics.track(name: "plain event")

        let plainEvent = capture.events.compactMap { $0 as? TrackEvent }.first { $0.event == "plain event" }
        XCTAssertNotNil(plainEvent)
        XCTAssertNil(plainEvent?.context?.dictionaryValue?["protocols"])
    }

    func testOmittedEnrichmentsLeavesEncodedPayloadUnchanged() throws {
        let (analytics, capture) = makeAnalytics(writeKey: "enrichEncodingTest")

        analytics.track(name: "plain event")
        analytics.track(name: "enriched event", enrichments: [schemaVersionEnrichment("v1")])

        let trackEvents = capture.events.compactMap { $0 as? TrackEvent }
        let plainEvent = try XCTUnwrap(trackEvents.first { $0.event == "plain event" })
        let enrichedEvent = try XCTUnwrap(trackEvents.first { $0.event == "enriched event" })

        XCTAssertNil(plainEvent.enrichments)
        XCTAssertNotNil(enrichedEvent.enrichments)

        func encodedKeys(_ event: TrackEvent) throws -> Set<String> {
            let data = try JSONEncoder().encode(event)
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return Set(object.keys)
        }

        let knownKeys: Set<String> = ["type", "anonymousId", "messageId", "userId", "timestamp",
                                      "context", "integrations", "metrics", "_metadata",
                                      "event", "properties"]

        let plainKeys = try encodedKeys(plainEvent)
        let enrichedKeys = try encodedKeys(enrichedEvent)

        // @Noncodable must keep the closures out of the encoded output entirely.
        XCTAssertFalse(plainKeys.contains("enrichments"))
        XCTAssertFalse(enrichedKeys.contains("enrichments"))
        XCTAssertTrue(plainKeys.isSubset(of: knownKeys), "Unexpected new keys: \(plainKeys.subtracting(knownKeys))")
        XCTAssertTrue(enrichedKeys.isSubset(of: knownKeys), "Unexpected new keys: \(enrichedKeys.subtracting(knownKeys))")
        XCTAssertEqual(plainKeys, enrichedKeys)
    }

    func testEnrichmentChangingEventTypeIsIgnored() {
        let (analytics, capture) = makeAnalytics(writeKey: "enrichTypeChangeTest")

        let typeChanger: EnrichmentClosure = { event in
            return IdentifyEvent(userId: "sneaky", traits: nil)
        }

        analytics.track(name: "type change", enrichments: [typeChanger, schemaVersionEnrichment("v2")])

        let event = capture.events.last as? TrackEvent
        XCTAssertNotNil(event, "Event type must not change; prior result should be kept.")
        XCTAssertEqual(event?.event, "type change")
        XCTAssertEqual(schemaVersion(of: event), "v2")
    }
}
