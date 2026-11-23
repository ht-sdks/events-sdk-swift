//
//  StartupQueue.swift
//  Segment
//
//  Created by Brandon Sneed on 6/4/21.
//

import Foundation
import Sovran

public class StartupQueue: Plugin, Subscriber {
    @Atomic public var running: Bool = false
    public let type: PluginType = .before

    public weak var analytics: Analytics? {
        didSet {
            analytics?.store.subscribe(self) { [weak self] (state: System) in
                self?.runningUpdate(state: state)
            }
        }
    }

    private let lock = NSRecursiveLock()
    private var nextIndex: Int?
    private var sessionEvents = [Int: RawEvent]()

    required init() { }

    private func files(in directory: URL) throws -> [Int: URL] {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var result = [Int: URL]()
        for url in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if let index = Int(url.lastPathComponent) { result[index] = url }
        }
        return result
    }

    public func execute<T: RawEvent>(event: T?) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard !running, let event = event, let analytics = analytics else { return event }
        let directory = analytics.storage.startupDirectory
        do {
            let index = try nextIndex ?? ((files(in: directory).keys.max() ?? -1) + 1)
            nextIndex = index + 1
            if event.enrichments?.isEmpty == false {
                sessionEvents[index] = event
                analytics.reportInternalError(AnalyticsError.enrichmentError(
                    "Startup events with enrichment callbacks can only be replayed in this session."
                ))
            } else {
                let file = directory.appendingPathComponent(String(index))
                try JSONEncoder().encode(event).write(to: file, options: .atomic)
            }
        } catch {
            let index = (nextIndex ?? 0)
            nextIndex = index + 1
            sessionEvents[index] = event
            analytics.reportInternalError(error)
        }
        return nil
    }

    internal func runningUpdate(state: System) {
        lock.lock()
        defer { lock.unlock() }
        running = state.running
        guard running, state.enabled, let analytics = analytics else { return }
        var saved = [Int: URL]()
        do { saved = try files(in: analytics.storage.startupDirectory) }
        catch { analytics.reportInternalError(error) }
        for index in Set(saved.keys).union(sessionEvents.keys).sorted() {
            if let event = sessionEvents.removeValue(forKey: index) {
                analytics.process(event: event)
            } else if let file = saved[index] {
                do {
                    let event = try Self.decode(Data(contentsOf: file))
                    analytics.process(event: event)
                    try FileManager.default.removeItem(at: file)
                } catch {
                    analytics.reportInternalError(error)
                }
            }
        }
    }

    private struct Header: Decodable { let type: String }

    internal static func decode(_ data: Data) throws -> RawEvent {
        let decoder = JSONDecoder()
        switch try decoder.decode(Header.self, from: data).type {
        case "track": return try decoder.decode(TrackEvent.self, from: data)
        case "identify": return try decoder.decode(IdentifyEvent.self, from: data)
        case "screen": return try decoder.decode(ScreenEvent.self, from: data)
        case "group": return try decoder.decode(GroupEvent.self, from: data)
        case "alias": return try decoder.decode(AliasEvent.self, from: data)
        default: throw AnalyticsError.storageInvalid("Unknown startup event type")
        }
    }
}
