//
//  SessionPlugin.swift
//
//
//  Created by Cursor on 6/9/26.
//

import Foundation

class SessionPlugin: PlatformPlugin, EventPlugin {
    let type = PluginType.enrichment
    weak var analytics: Analytics?

    var now: () -> Int64 = {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private var isAppInBackground = false

    func execute<T: RawEvent>(event: T?) -> T? {
        guard let analytics = analytics, var workingEvent = event else {
            return event
        }

        let currentTime = now()
        let messageId = workingEvent.messageId ?? ""
        let timestamp = workingEvent.timestamp ?? Date(timeIntervalSince1970: TimeInterval(currentTime) / 1000).iso8601()
        let configuration = analytics.configuration.values
        var contextSession: ContextSession?

        updateSessionState { state in
            let result = SessionPluginHelper.processEvent(state: state,
                                                          now: currentTime,
                                                          messageId: messageId,
                                                          timestamp: timestamp,
                                                          foregroundSessionTimeout: configuration.foregroundSessionTimeout,
                                                          backgroundSessionTimeout: configuration.backgroundSessionTimeout,
                                                          isAppInBackground: self.isAppInBackground)
            contextSession = result.contextSession
            return result.sessionState
        }

        guard let contextSession = contextSession else {
            return workingEvent
        }

        workingEvent.context = addSessionContext(to: workingEvent.context, contextSession: contextSession)
        return workingEvent
    }

    func reset() {
        guard analytics != nil else { return }

        let currentTime = now()
        updateSessionState { state in
            return SessionPluginHelper.rotateSession(state: state,
                                                     now: currentTime,
                                                     firstEventId: state?.firstEventId ?? "",
                                                     firstEventTimestamp: Date(timeIntervalSince1970: TimeInterval(currentTime) / 1000).iso8601())
        }
    }

    private func addSessionContext(to eventContext: JSON?, contextSession: ContextSession) -> JSON? {
        var context = eventContext?.dictionaryValue ?? [:]
        context.removeValue(forKey: "sessionStart")
        context["session"] = sessionDictionary(from: contextSession)
        context["sessionId"] = contextSession.sessionId
        if contextSession.sessionStart == true {
            context["sessionStart"] = true
        }

        return try? JSON(context)
    }

    private func sessionDictionary(from contextSession: ContextSession) -> [String: Any] {
        var session: [String: Any] = [
            "sessionId": contextSession.sessionId,
            "sessionIndex": contextSession.sessionIndex,
            "eventIndex": contextSession.eventIndex,
            "previousSessionId": contextSession.previousSessionId.map { $0 as Any } ?? NSNull(),
            "firstEventId": contextSession.firstEventId,
            "firstEventTimestamp": contextSession.firstEventTimestamp
        ]

        if contextSession.sessionStart == true {
            session["sessionStart"] = true
        }

        return session
    }

    private func markBackgrounded() {
        guard analytics != nil else { return }
        guard !isAppInBackground else { return }
        isAppInBackground = true

        let currentTime = now()
        updateSessionState { state in
            return SessionPluginHelper.markBackgrounded(state: state, now: currentTime)
        }
    }

    private func markForegrounded() {
        guard let analytics = analytics else { return }
        guard isAppInBackground else { return }
        isAppInBackground = false

        let currentTime = now()
        let backgroundSessionTimeout = analytics.configuration.values.backgroundSessionTimeout
        updateSessionState { state in
            return SessionPluginHelper.markForegrounded(state: state,
                                                        now: currentTime,
                                                        backgroundSessionTimeout: backgroundSessionTimeout)
        }
    }

    private func updateSessionState(_ update: @escaping (SessionState?) -> SessionState?) {
        guard let analytics = analytics else { return }

        analytics.store.dispatch(action: SessionInfo.UpdateSessionAction(update: update))
        let sessionInfo: SessionInfo? = analytics.store.currentState()
        analytics.storage.write(.sessionState, value: sessionInfo?.sessionState)
    }
}

#if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
import UIKit

extension SessionPlugin: iOSLifecycle {
    func applicationWillResignActive(application: UIApplication?) {
        markBackgrounded()
    }

    func applicationDidEnterBackground(application: UIApplication?) {
        markBackgrounded()
    }

    func applicationWillEnterForeground(application: UIApplication?) {
        markForegrounded()
    }

    func applicationDidBecomeActive(application: UIApplication?) {
        markForegrounded()
    }
}
#endif

#if os(macOS)
import Cocoa

extension SessionPlugin: macOSLifecycle {
    func applicationDidResignActive() {
        markBackgrounded()
    }

    func applicationDidHide() {
        markBackgrounded()
    }

    func applicationWillBecomeActive() {
        markForegrounded()
    }

    func applicationDidBecomeActive() {
        markForegrounded()
    }

    func applicationDidUnhide() {
        markForegrounded()
    }
}
#endif

#if os(watchOS)
import WatchKit

extension SessionPlugin: watchOSLifecycle {
    func applicationDidEnterBackground(watchExtension: WKExtension) {
        markBackgrounded()
    }

    func applicationWillResignActive(watchExtension: WKExtension) {
        markBackgrounded()
    }

    func applicationWillEnterForeground(watchExtension: WKExtension) {
        markForegrounded()
    }

    func applicationDidBecomeActive(watchExtension: WKExtension) {
        markForegrounded()
    }
}
#endif

