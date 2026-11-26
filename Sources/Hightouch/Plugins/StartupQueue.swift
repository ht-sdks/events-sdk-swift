//
//  StartupQueue.swift
//  Segment
//
//  Created by Brandon Sneed on 6/4/21.
//

import Foundation
import Sovran

public class StartupQueue: Plugin, Subscriber {
    static let maxSize = 1000

    @Atomic public var running: Bool = false
    
    public let type: PluginType = .before
    
    public weak var analytics: Analytics? = nil {
        didSet {
            analytics?.store.subscribe(self) { [weak self] (state: System) in
                self?.runningUpdate(state: state)
            }
        }
    }
    
    let syncQueue = DispatchQueue(label: "startupQueue.hightouch.com")
    var queuedEvents = [RawEvent]()
    
    required init() { }
    
    public func execute<T: RawEvent>(event: T?) -> T? {
        guard let event = event, !running else { return event }
        return syncQueue.sync {
            // Readiness may have changed while admission waited for the queue.
            guard !running else { return event }
            if queuedEvents.count >= Self.maxSize {
                queuedEvents.removeFirst()
            }
            queuedEvents.append(event)
            return nil
        }
    }
}

extension StartupQueue {
    internal func runningUpdate(state: System) {
        let pending: [RawEvent] = syncQueue.sync {
            running = state.running
            guard running else { return [] }
            let events = queuedEvents
            queuedEvents.removeAll()
            return events
        }
        for event in pending {
            analytics?.process(event: event)
        }
    }
}
