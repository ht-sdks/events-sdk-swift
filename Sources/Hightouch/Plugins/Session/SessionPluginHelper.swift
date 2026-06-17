//
//  SessionPluginHelper.swift
//
//
//  Created by Cursor on 6/9/26.
//

import Foundation

struct ContextSession: Equatable {
    let sessionId: Int64
    let sessionIndex: Int
    let sessionStart: Bool?
    let eventIndex: Int
    let previousSessionId: Int64?
    let firstEventId: String
    let firstEventTimestamp: String
}

struct EnrichedSessionEvent: Equatable {
    let contextSession: ContextSession
    let sessionState: SessionState
}

enum SessionPluginHelper {
    static func isValidSessionTimeout(_ timeout: Int) -> Bool {
        return timeout >= 0
    }

    static func isEnabled(foregroundSessionTimeout: Int, backgroundSessionTimeout: Int) -> Bool {
        return !(foregroundSessionTimeout == 0 && backgroundSessionTimeout == 0)
    }

    static func isEnabled(_ config: Configuration.Values) -> Bool {
        return isEnabled(foregroundSessionTimeout: config.foregroundSessionTimeout,
                         backgroundSessionTimeout: config.backgroundSessionTimeout)
    }

    static func shouldRotateOnResume(state: SessionState?,
                                     now: Int64,
                                     backgroundSessionTimeout: Int = 0) -> Bool {
        guard let backgroundedAt = state?.backgroundedAt, backgroundSessionTimeout > 0 else {
            return false
        }

        return now - backgroundedAt > Int64(backgroundSessionTimeout)
    }

    static func shouldRotateOnInactivity(state: SessionState?,
                                         now: Int64,
                                         foregroundSessionTimeout: Int = 0) -> Bool {
        guard let state = state, foregroundSessionTimeout > 0 else {
            return false
        }

        return now - state.lastActivityAt > Int64(foregroundSessionTimeout)
    }

    static func rotateSession(state: SessionState?,
                              now: Int64,
                              firstEventId: String,
                              firstEventTimestamp: String) -> SessionState {
        return SessionState(sessionId: now,
                            sessionIndex: state == nil ? 0 : state!.sessionIndex + 1,
                            previousSessionId: state?.sessionId,
                            firstEventId: firstEventId,
                            firstEventTimestamp: firstEventTimestamp,
                            eventIndex: 0,
                            lastActivityAt: now,
                            backgroundedAt: nil)
    }

    static func enrichEvent(state: SessionState,
                            now: Int64,
                            updateActivity: Bool = true) -> EnrichedSessionEvent {
        let sessionStart = state.eventIndex == 0
        let contextSession = ContextSession(sessionId: state.sessionId,
                                            sessionIndex: state.sessionIndex,
                                            sessionStart: sessionStart ? true : nil,
                                            eventIndex: state.eventIndex,
                                            previousSessionId: state.previousSessionId,
                                            firstEventId: state.firstEventId,
                                            firstEventTimestamp: state.firstEventTimestamp)
        let sessionState = SessionState(sessionId: state.sessionId,
                                        sessionIndex: state.sessionIndex,
                                        previousSessionId: state.previousSessionId,
                                        firstEventId: state.firstEventId,
                                        firstEventTimestamp: state.firstEventTimestamp,
                                        eventIndex: state.eventIndex + 1,
                                        lastActivityAt: updateActivity ? now : state.lastActivityAt,
                                        backgroundedAt: updateActivity ? nil : state.backgroundedAt)

        return EnrichedSessionEvent(contextSession: contextSession, sessionState: sessionState)
    }

    static func ensureFirstEvent(state: SessionState,
                                 messageId: String,
                                 timestamp: String) -> SessionState {
        if state.eventIndex != 0 || state.firstEventId != "" {
            return state
        }

        return SessionState(sessionId: state.sessionId,
                            sessionIndex: state.sessionIndex,
                            previousSessionId: state.previousSessionId,
                            firstEventId: messageId,
                            firstEventTimestamp: timestamp,
                            eventIndex: state.eventIndex,
                            lastActivityAt: state.lastActivityAt,
                            backgroundedAt: state.backgroundedAt)
    }

    static func processEvent(state: SessionState?,
                             now: Int64,
                             messageId: String,
                             timestamp: String,
                             foregroundSessionTimeout: Int = 0,
                             backgroundSessionTimeout: Int = 0,
                             isAppInBackground: Bool = false) -> EnrichedSessionEvent {
        let shouldRotate = state == nil ||
            (!isAppInBackground &&
                (shouldRotateOnResume(state: state,
                                      now: now,
                                      backgroundSessionTimeout: backgroundSessionTimeout) ||
                 shouldRotateOnInactivity(state: state,
                                          now: now,
                                          foregroundSessionTimeout: foregroundSessionTimeout)))

        let currentState = shouldRotate
            ? rotateSession(state: state, now: now, firstEventId: messageId, firstEventTimestamp: timestamp)
            : ensureFirstEvent(state: state!, messageId: messageId, timestamp: timestamp)

        return enrichEvent(state: currentState, now: now, updateActivity: !isAppInBackground)
    }

    static func markBackgrounded(state: SessionState?, now: Int64) -> SessionState? {
        guard let state = state else {
            return state
        }

        return SessionState(sessionId: state.sessionId,
                            sessionIndex: state.sessionIndex,
                            previousSessionId: state.previousSessionId,
                            firstEventId: state.firstEventId,
                            firstEventTimestamp: state.firstEventTimestamp,
                            eventIndex: state.eventIndex,
                            lastActivityAt: state.lastActivityAt,
                            backgroundedAt: state.backgroundedAt ?? now)
    }

    static func markForegrounded(state: SessionState?,
                                 now: Int64,
                                 backgroundSessionTimeout: Int = 0) -> SessionState? {
        guard let state = state else {
            return state
        }

        if shouldRotateOnResume(state: state, now: now, backgroundSessionTimeout: backgroundSessionTimeout) {
            return state
        }

        return SessionState(sessionId: state.sessionId,
                            sessionIndex: state.sessionIndex,
                            previousSessionId: state.previousSessionId,
                            firstEventId: state.firstEventId,
                            firstEventTimestamp: state.firstEventTimestamp,
                            eventIndex: state.eventIndex,
                            lastActivityAt: now,
                            backgroundedAt: nil)
    }
}

