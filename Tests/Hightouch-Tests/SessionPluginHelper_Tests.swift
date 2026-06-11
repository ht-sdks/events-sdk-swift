//
//  SessionPluginHelper_Tests.swift
//
//
//  Created by Cursor on 6/9/26.
//

import XCTest
@testable import Hightouch

final class SessionPluginHelper_Tests: XCTestCase {
    private let initialState = SessionState(sessionId: 1000,
                                            sessionIndex: 0,
                                            previousSessionId: nil,
                                            firstEventId: "first-message-id",
                                            firstEventTimestamp: "2026-01-01T00:00:01.000Z",
                                            eventIndex: 1,
                                            lastActivityAt: 1000,
                                            backgroundedAt: nil)

    func testCreatesFirstSessionOnFirstEvent() {
        let result = SessionPluginHelper.processEvent(state: nil,
                                                      now: 1000,
                                                      messageId: "message-id",
                                                      timestamp: "2026-01-01T00:00:01.000Z",
                                                      foregroundSessionTimeout: 1_800_000,
                                                      backgroundSessionTimeout: 1_800_000)

        XCTAssertEqual(result.contextSession,
                       ContextSession(sessionId: 1000,
                                      sessionIndex: 0,
                                      sessionStart: true,
                                      eventIndex: 0,
                                      previousSessionId: nil,
                                      firstEventId: "message-id",
                                      firstEventTimestamp: "2026-01-01T00:00:01.000Z"))
        XCTAssertEqual(result.sessionState,
                       SessionState(sessionId: 1000,
                                    sessionIndex: 0,
                                    previousSessionId: nil,
                                    firstEventId: "message-id",
                                    firstEventTimestamp: "2026-01-01T00:00:01.000Z",
                                    eventIndex: 1,
                                    lastActivityAt: 1000,
                                    backgroundedAt: nil))
    }

    func testIncrementsEventIndexWithinSession() {
        let result = SessionPluginHelper.processEvent(state: initialState,
                                                      now: 2000,
                                                      messageId: "second-message-id",
                                                      timestamp: "2026-01-01T00:00:02.000Z",
                                                      foregroundSessionTimeout: 1_800_000,
                                                      backgroundSessionTimeout: 1_800_000)

        XCTAssertEqual(result.contextSession,
                       ContextSession(sessionId: 1000,
                                      sessionIndex: 0,
                                      sessionStart: nil,
                                      eventIndex: 1,
                                      previousSessionId: nil,
                                      firstEventId: "first-message-id",
                                      firstEventTimestamp: "2026-01-01T00:00:01.000Z"))
        XCTAssertEqual(result.sessionState.eventIndex, 2)
        XCTAssertEqual(result.sessionState.lastActivityAt, 2000)
    }

    func testRotatesAfterForegroundInactivityExceedsTimeout() {
        let result = SessionPluginHelper.processEvent(state: initialState,
                                                      now: 3000,
                                                      messageId: "new-session-message-id",
                                                      timestamp: "2026-01-01T00:00:03.000Z",
                                                      foregroundSessionTimeout: 1999,
                                                      backgroundSessionTimeout: 1_800_000)

        XCTAssertEqual(result.contextSession,
                       ContextSession(sessionId: 3000,
                                      sessionIndex: 1,
                                      sessionStart: true,
                                      eventIndex: 0,
                                      previousSessionId: 1000,
                                      firstEventId: "new-session-message-id",
                                      firstEventTimestamp: "2026-01-01T00:00:03.000Z"))
    }

    func testRotatesOnFirstEventAfterLongBackgroundDuration() {
        let backgroundedState = SessionState(sessionId: initialState.sessionId,
                                             sessionIndex: initialState.sessionIndex,
                                             previousSessionId: initialState.previousSessionId,
                                             firstEventId: initialState.firstEventId,
                                             firstEventTimestamp: initialState.firstEventTimestamp,
                                             eventIndex: initialState.eventIndex,
                                             lastActivityAt: initialState.lastActivityAt,
                                             backgroundedAt: 1500)

        let foregroundedState = SessionPluginHelper.markForegrounded(state: backgroundedState,
                                                                     now: 4000,
                                                                     backgroundSessionTimeout: 2000)
        let result = SessionPluginHelper.processEvent(state: foregroundedState,
                                                      now: 4000,
                                                      messageId: "foreground-message-id",
                                                      timestamp: "2026-01-01T00:00:04.000Z",
                                                      foregroundSessionTimeout: 1_800_000,
                                                      backgroundSessionTimeout: 2000)

        XCTAssertEqual(result.contextSession,
                       ContextSession(sessionId: 4000,
                                      sessionIndex: 1,
                                      sessionStart: true,
                                      eventIndex: 0,
                                      previousSessionId: 1000,
                                      firstEventId: "foreground-message-id",
                                      firstEventTimestamp: "2026-01-01T00:00:04.000Z"))
    }

    func testPreservesBackgroundedAtWhenRebackgroundingWithPendingRotation() {
        let backgroundedState = SessionState(sessionId: initialState.sessionId,
                                             sessionIndex: initialState.sessionIndex,
                                             previousSessionId: initialState.previousSessionId,
                                             firstEventId: initialState.firstEventId,
                                             firstEventTimestamp: initialState.firstEventTimestamp,
                                             eventIndex: initialState.eventIndex,
                                             lastActivityAt: initialState.lastActivityAt,
                                             backgroundedAt: 1500)

        let foregroundedState = SessionPluginHelper.markForegrounded(state: backgroundedState,
                                                                     now: 4000,
                                                                     backgroundSessionTimeout: 2000)
        XCTAssertEqual(foregroundedState?.backgroundedAt, 1500)

        let rebackgroundedState = SessionPluginHelper.markBackgrounded(state: foregroundedState, now: 5100)
        XCTAssertEqual(rebackgroundedState?.backgroundedAt, 1500)

        let result = SessionPluginHelper.processEvent(state: rebackgroundedState,
                                                      now: 5200,
                                                      messageId: "delayed-rotation-message-id",
                                                      timestamp: "2026-01-01T00:00:05.200Z",
                                                      foregroundSessionTimeout: 1_800_000,
                                                      backgroundSessionTimeout: 2000)

        XCTAssertEqual(result.contextSession,
                       ContextSession(sessionId: 5200,
                                      sessionIndex: 1,
                                      sessionStart: true,
                                      eventIndex: 0,
                                      previousSessionId: 1000,
                                      firstEventId: "delayed-rotation-message-id",
                                      firstEventTimestamp: "2026-01-01T00:00:05.200Z"))
    }

    func testColdStartRotatesWhenPersistedBackgroundedAtExceeded() {
        let backgroundedState = SessionState(sessionId: initialState.sessionId,
                                             sessionIndex: initialState.sessionIndex,
                                             previousSessionId: initialState.previousSessionId,
                                             firstEventId: initialState.firstEventId,
                                             firstEventTimestamp: initialState.firstEventTimestamp,
                                             eventIndex: initialState.eventIndex,
                                             lastActivityAt: initialState.lastActivityAt,
                                             backgroundedAt: 1500)

        let result = SessionPluginHelper.processEvent(state: backgroundedState,
                                                      now: 4000,
                                                      messageId: "cold-start-message-id",
                                                      timestamp: "2026-01-01T00:00:04.000Z",
                                                      foregroundSessionTimeout: 1_800_000,
                                                      backgroundSessionTimeout: 2000)

        XCTAssertEqual(result.contextSession.sessionId, 4000)
        XCTAssertEqual(result.contextSession.sessionIndex, 1)
        XCTAssertEqual(result.contextSession.previousSessionId, 1000)
        XCTAssertEqual(result.contextSession.sessionStart, true)
        XCTAssertEqual(result.contextSession.eventIndex, 0)
    }

    func testRotateSessionOnResetIncrementsSessionIndex() {
        let result = SessionPluginHelper.rotateSession(state: initialState,
                                                       now: 5000,
                                                       firstEventId: initialState.firstEventId,
                                                       firstEventTimestamp: "2026-01-01T00:00:05.000Z")

        XCTAssertEqual(result.sessionId, 5000)
        XCTAssertEqual(result.sessionIndex, 1)
        XCTAssertEqual(result.previousSessionId, 1000)
        XCTAssertEqual(result.eventIndex, 0)
    }

    func testRejectsNegativeSessionTimeouts() {
        XCTAssertFalse(SessionPluginHelper.isValidSessionTimeout(-1))
        XCTAssertTrue(SessionPluginHelper.isValidSessionTimeout(0))
        XCTAssertTrue(SessionPluginHelper.isValidSessionTimeout(1_800_000))
    }

    func testIsEnabledOnlyFalseWhenBothTimeoutsAreZero() {
        XCTAssertTrue(SessionPluginHelper.isEnabled(foregroundSessionTimeout: 1, backgroundSessionTimeout: 0))
        XCTAssertTrue(SessionPluginHelper.isEnabled(foregroundSessionTimeout: 0, backgroundSessionTimeout: 1))
        XCTAssertTrue(SessionPluginHelper.isEnabled(foregroundSessionTimeout: 1, backgroundSessionTimeout: 1))
        XCTAssertFalse(SessionPluginHelper.isEnabled(foregroundSessionTimeout: 0, backgroundSessionTimeout: 0))
    }
}

