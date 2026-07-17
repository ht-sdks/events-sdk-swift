import Foundation
@testable import Hightouch

// Mirror of the helpers in `Tests/Hightouch-Tests/Support/TestUtilities.swift`. SPM test targets
// cannot depend on one another, so the push test target keeps its own copy (see AGENTS.md
// "Testing Patterns").

/// An `.after` plugin that captures dispatched events for assertions.
class OutputReaderPlugin: Plugin {
    let type: PluginType
    var analytics: Analytics?

    var events = [RawEvent]()
    var lastEvent: RawEvent?

    init() {
        self.type = .after
    }

    func execute<T>(event: T?) -> T? where T: RawEvent {
        lastEvent = event
        if let t = lastEvent as? TrackEvent {
            events.append(t)
        }
        return event
    }
}

/// Spins the run loop until the analytics `StartupQueue` has finished, so events dispatched
/// afterwards flow synchronously through the timeline (and reach `OutputReaderPlugin`).
func waitUntilStarted(analytics: Analytics?) {
    guard let analytics = analytics else { return }
    if let startupQueue = analytics.find(pluginType: StartupQueue.self) {
        while startupQueue.running != true {
            RunLoop.main.run(until: Date.distantPast)
        }
    }
}
