import XCTest
@testable import HightouchPush
import Hightouch

#if canImport(CoreData) && (os(iOS) || os(macOS) || targetEnvironment(macCatalyst))
import CoreData

final class StubMessagesURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var queuedResponses: [(status: Int, body: Data)] = []
    private static var lastResponse: (status: Int, body: Data) = (200, Data(#"{"messages":[]}"#.utf8))
    private(set) static var requestCount = 0
    private(set) static var capturedRequests: [URLRequest] = []
    private(set) static var capturedBodies: [Data?] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queuedResponses = []
        lastResponse = (200, Data(#"{"messages":[]}"#.utf8))
        requestCount = 0
        capturedRequests = []
        capturedBodies = []
    }

    private static func extractBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    static func enqueue(status: Int, body: Data) {
        lock.lock(); defer { lock.unlock() }
        queuedResponses.append((status, body))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override var cachedResponse: CachedURLResponse? { nil }

    override func startLoading() {
        StubMessagesURLProtocol.lock.lock()
        StubMessagesURLProtocol.requestCount += 1
        StubMessagesURLProtocol.capturedRequests.append(request)
        StubMessagesURLProtocol.capturedBodies.append(StubMessagesURLProtocol.extractBody(from: request))
        let next: (status: Int, body: Data)
        if !StubMessagesURLProtocol.queuedResponses.isEmpty {
            next = StubMessagesURLProtocol.queuedResponses.removeFirst()
            StubMessagesURLProtocol.lastResponse = next
        } else {
            next = StubMessagesURLProtocol.lastResponse
        }
        StubMessagesURLProtocol.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: next.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Inserts the duplicate pair directly on writeContext, so this tests the schema constraint rather than replaceAll.
private final class ErrorCounter {
    private let lock = NSLock()
    private var _count = 0
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    func increment() {
        lock.lock(); _count += 1; lock.unlock()
    }
}

final class MessagesSync_Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubMessagesURLProtocol.reset()
    }

    override func tearDown() {
        StubMessagesURLProtocol.reset()
        super.tearDown()
    }

    // Resubmit aOld each time: replaceAll is replace-from-server and would otherwise delete it.

    static let deviceToken = "0a1b2c3d4e5f"

    private func makeStore() throws -> MessageStore {
        try MessageStore(location: .ephemeral)
    }

    private func makeAnalytics(writeKey: String, errorCounter: ErrorCounter? = nil) -> Analytics {
        var configuration = Configuration(writeKey: writeKey)
        if let errorCounter = errorCounter {
            configuration = configuration.errorHandler { _ in errorCounter.increment() }
        }
        return Analytics(configuration: configuration)
    }

    private func makeCoordinator(
        analytics: Analytics,
        store: MessageStore,
        config: HightouchMessagesConfig = HightouchMessagesConfig(),
        ownerProvider: @escaping (Analytics) -> MessageOwner?,
        deviceTokenProvider: @escaping () -> String? = { MessagesSync_Tests.deviceToken }
    ) -> MessagesSyncCoordinator {
        let client = MessagesHTTPClient(analytics: analytics, config: config, protocolClasses: [StubMessagesURLProtocol.self])
        return MessagesSyncCoordinator(
            analytics: analytics,
            config: config,
            store: store,
            client: client,
            userDefaults: UserDefaults(suiteName: "MessagesSync_Tests-\(UUID().uuidString)")!,
            ownerProvider: ownerProvider,
            deviceTokenProvider: deviceTokenProvider
        )
    }

    private func messagesBody(_ ids: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["messages": ids.map { ["messageId": $0] }])
    }

    @discardableResult
    private func syncSync(_ coordinator: MessagesSyncCoordinator, force: Bool = true) throws -> Result<HightouchMessagesChange, Error> {
        let completed = expectation(description: "sync")
        var outcome: Result<HightouchMessagesChange, Error>?
        coordinator.sync(force: force) { result in
            outcome = result
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        return try XCTUnwrap(outcome)
    }

    // Interleave owners so a per-owner cap and a global cap would disagree.

    func test200With3MessagesStoresRowsAndFiresExactlyOneChangeNotificationOnMain() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-1")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })
        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1", "m2", "m3"]))

        var notificationCount = 0
        var notificationWasOnMain = false
        let notified = expectation(description: "change notification")
        let observer = NotificationCenter.default.addObserver(forName: .hightouchMessagesDidChange, object: nil, queue: nil) { _ in
            notificationCount += 1
            notificationWasOnMain = Thread.isMainThread
            notified.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = try syncSync(coordinator)
        wait(for: [notified], timeout: 5)

        let settled = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        guard case .success(let change) = result else { return XCTFail("expected success") }
        XCTAssertEqual(Set(change.insertedIds), ["m1", "m2", "m3"])
        XCTAssertEqual(notificationCount, 1)
        XCTAssertTrue(notificationWasOnMain, "the change notification must be posted on the main thread")
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 1)

        let stored = store.messages(matching: HightouchMessageQuery(), owner: owner)
        XCTAssertEqual(Set(stored.map { $0.messageId }), ["m1", "m2", "m3"])
    }

    // MARK: - Malformed messages

    func testOneMalformedMessageAmongThreeStillPersistsTheOthersAndReportsErrorOnce() throws {
        let store = try makeStore()
        let errorCounter = ErrorCounter()
        let analytics = makeAnalytics(writeKey: "\(name)-2", errorCounter: errorCounter)
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })

        let body = try JSONSerialization.data(withJSONObject: [
            "messages": [
                ["messageId": "m1"],
                ["notAnId": "oops"],
                ["messageId": "m2"],
            ]
        ])
        StubMessagesURLProtocol.enqueue(status: 200, body: body)

        let result = try syncSync(coordinator)
        guard case .success = result else { return XCTFail("expected success despite the malformed row") }

        let stored = store.messages(matching: HightouchMessageQuery(), owner: owner)
        XCTAssertEqual(Set(stored.map { $0.messageId }), ["m1", "m2"])
        XCTAssertEqual(errorCounter.count, 1, "one malformed row should report exactly once, not per-row")
    }

    // MARK: - Bare top-level array envelope

    func testBareTopLevelArrayEnvelopeIsAccepted() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-3")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })

        let body = try JSONSerialization.data(withJSONObject: [["messageId": "m1"], ["messageId": "m2"]])
        StubMessagesURLProtocol.enqueue(status: 200, body: body)

        let result = try syncSync(coordinator)
        guard case .success(let change) = result else { return XCTFail("expected success") }
        XCTAssertEqual(Set(change.insertedIds), ["m1", "m2"])
    }

    // Compare components: some Foundation versions add a trailing slash once the directory exists.

    func test500RetriesOnceThenFailsAndLeavesTheStoreUnchanged() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-4")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")

        let seeded = expectation(description: "seed")
        store.replaceAll([try HightouchMessage(raw: try JSON(["messageId": "existing"]))], owner: owner) { _ in seeded.fulfill() }
        wait(for: [seeded], timeout: 5)

        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })
        StubMessagesURLProtocol.enqueue(status: 500, body: Data())
        StubMessagesURLProtocol.enqueue(status: 500, body: Data())

        let result = try syncSync(coordinator)
        guard case .failure = result else { return XCTFail("expected failure after the retry also fails") }

        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 2, "exactly one retry after the initial 500")
        XCTAssertEqual(
            store.messages(matching: HightouchMessageQuery(), owner: owner).map { $0.messageId },
            ["existing"],
            "a failed sync must not touch what was already stored"
        )
    }

    func test401DoesNotRetry() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-5")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })
        StubMessagesURLProtocol.enqueue(status: 401, body: Data())

        let result = try syncSync(coordinator)
        guard case .failure = result else { return XCTFail("expected failure") }
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 1, "a 4xx must never be retried")
    }

    func test400DoesNotRetry() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-6")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })
        StubMessagesURLProtocol.enqueue(status: 400, body: Data())

        let result = try syncSync(coordinator)
        guard case .failure = result else { return XCTFail("expected failure") }
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 1, "a 4xx must never be retried")
    }

    // MARK: - Coalescing

    func testTwoBackToBackSyncCallsIssueExactlyOneHTTPRequest() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-7")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })
        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1"]))

        let first = expectation(description: "first completion")
        let second = expectation(description: "second completion")
        coordinator.sync(force: false) { _ in first.fulfill() }
        coordinator.sync(force: false) { _ in second.fulfill() }
        wait(for: [first, second], timeout: 5)

        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 1, "a request already in flight must not trigger a second one")
    }

    func testForcedSyncDuringAnInFlightRequestFetchesAgainAfterIt() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-forced-follow-up")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })
        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1"]))
        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1", "m2"]))
        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1", "m2", "m3"]))

        let first = expectation(description: "in-flight sync")
        let second = expectation(description: "first forced sync")
        let third = expectation(description: "second forced sync")
        var forcedChanges: [HightouchMessagesChange] = []
        coordinator.sync(force: false) { _ in first.fulfill() }
        coordinator.sync(force: true) { result in
            if case .success(let change) = result { forcedChanges.append(change) }
            second.fulfill()
        }
        coordinator.sync(force: true) { result in
            if case .success(let change) = result { forcedChanges.append(change) }
            third.fulfill()
        }
        wait(for: [first, second, third], timeout: 5)

        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 2, "forced syncs queue one follow-up fetch, coalesced")
        XCTAssertEqual(forcedChanges.map { Set($0.insertedIds) }, [["m2"], ["m2"]], "forced callers get the follow-up's result")
        XCTAssertEqual(Set(store.messages(matching: HightouchMessageQuery(), owner: owner).map { $0.messageId }), ["m1", "m2"])
    }

    func testAnonymousOwnerMakesNoHTTPRequest() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-anonymous")
        let owner = MessageOwner(kind: .anonymousId, id: "anon-\(name)")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })

        let result = try syncSync(coordinator)
        guard case .success(let change) = result else { return XCTFail("an anonymous owner must report success/no-op") }
        XCTAssertTrue(change.insertedIds.isEmpty && change.updatedIds.isEmpty && change.removedIds.isEmpty)
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 0, "the gateway always returns an empty inbox for anonymous ids")
    }

    func testA200WithoutAMessagesArrayFailsAndKeepsTheCache() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-missing-array")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })
        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1"]))
        _ = try syncSync(coordinator)

        StubMessagesURLProtocol.enqueue(status: 200, body: Data(#"{"error":"upstream"}"#.utf8))
        StubMessagesURLProtocol.enqueue(status: 200, body: Data(#"{"messages":null}"#.utf8))
        let result = try syncSync(coordinator)

        guard case .failure = result else { return XCTFail("a body without a messages array must fail the sync") }
        XCTAssertEqual(store.messages(matching: HightouchMessageQuery(), owner: owner).map { $0.messageId }, ["m1"])
    }

    func testSyncThatDoesNotUpdateTheCooldownLeavesTheNextUnforcedSyncFree() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-no-stamp")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        var config = HightouchMessagesConfig()
        config.foregroundSyncCooldown = 3600
        let coordinator = makeCoordinator(analytics: analytics, store: store, config: config, ownerProvider: { _ in owner })

        let first = expectation(description: "identity sync")
        coordinator.sync(force: false, updatesCooldown: false) { _ in first.fulfill() }
        wait(for: [first], timeout: 5)
        _ = try syncSync(coordinator, force: false)

        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 2, "an unstamped sync must not start the cooldown")
    }

    // MARK: - Store cap

    func testAnOwnerOverTheCapConvergesAndEvictsOnlyOtherOwners() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-cap")
        let alice = MessageOwner(kind: .userId, id: "alice-\(name)")
        let bob = MessageOwner(kind: .userId, id: "bob-\(name)")
        var owner = bob
        var config = HightouchMessagesConfig()
        config.maxStoredMessages = 2
        let coordinator = makeCoordinator(analytics: analytics, store: store, config: config, ownerProvider: { _ in owner })

        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["b1"]))
        _ = try syncSync(coordinator)

        owner = alice
        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["a1", "a2", "a3"]))
        guard case .success(let first) = try syncSync(coordinator) else { return XCTFail("expected success") }
        XCTAssertEqual(first.insertedIds.count, 2)
        XCTAssertEqual(store.messages(matching: HightouchMessageQuery(), owner: alice).count, 2)
        XCTAssertTrue(store.messages(matching: HightouchMessageQuery(), owner: bob).isEmpty, "other owners' rows are evicted first")

        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["a1", "a2", "a3"]))
        guard case .success(let second) = try syncSync(coordinator) else { return XCTFail("expected success") }
        XCTAssertTrue(second.insertedIds.isEmpty && second.removedIds.isEmpty, "the same server set must not churn")
    }

    // MARK: - Cooldown

    func testCooldownBlocksASecondSyncButForceBypassesIt() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-8")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        var config = HightouchMessagesConfig()
        config.foregroundSyncCooldown = 3600
        let coordinator = makeCoordinator(analytics: analytics, store: store, config: config, ownerProvider: { _ in owner })

        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1"]))
        let firstCompleted = expectation(description: "first sync")
        coordinator.sync(force: false) { _ in firstCompleted.fulfill() }
        wait(for: [firstCompleted], timeout: 5)
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 1)

        let secondResult = try {
            let completed = expectation(description: "second sync (within cooldown)")
            var outcome: Result<HightouchMessagesChange, Error>?
            coordinator.sync(force: false) { result in
                outcome = result
                completed.fulfill()
            }
            wait(for: [completed], timeout: 5)
            return try XCTUnwrap(outcome)
        }()
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 1, "the cooldown must block a second unforced sync")
        guard case .success(let unchanged) = secondResult else { return XCTFail("cooldown-skip must report success, not failure") }
        XCTAssertTrue(unchanged.insertedIds.isEmpty && unchanged.updatedIds.isEmpty && unchanged.removedIds.isEmpty)

        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1"]))
        let thirdCompleted = expectation(description: "third sync (forced)")
        coordinator.sync(force: true) { _ in thirdCompleted.fulfill() }
        wait(for: [thirdCompleted], timeout: 5)
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 2, "force: true must bypass the cooldown")
    }

    // MARK: - No identity, no fetch

    func testNoIdentityMeansNoHTTPRequestAtAll() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-9")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in nil })

        let result = try syncSync(coordinator)
        guard case .success(let change) = result else { return XCTFail("no identity must report success/no-op, not failure") }
        XCTAssertTrue(change.insertedIds.isEmpty && change.updatedIds.isEmpty && change.removedIds.isEmpty)
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 0, "no identity to scope to means no HTTP call at all")
    }

    // MARK: - Replace-from-server

    func testSecondSyncOmittingAPreviouslyStoredMessageRemovesItLocally() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-10")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in owner })

        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1", "m2"]))
        _ = try syncSync(coordinator)
        XCTAssertEqual(Set(store.messages(matching: HightouchMessageQuery(), owner: owner).map { $0.messageId }), ["m1", "m2"])

        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1"]))
        let result = try syncSync(coordinator)
        guard case .success(let change) = result else { return XCTFail("expected success") }
        XCTAssertEqual(change.removedIds, ["m2"])
        XCTAssertEqual(store.messages(matching: HightouchMessageQuery(), owner: owner).map { $0.messageId }, ["m1"])
    }

    // MARK: - No device token, no fetch

    // Stored: an NSEntityDescription doesn't retain its model, so a computed model leaves `entity` dangling.
    func testNoDeviceTokenMeansNoHTTPRequestAtAll() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-no-token")
        let owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        let coordinator = makeCoordinator(
            analytics: analytics, store: store, ownerProvider: { _ in owner }, deviceTokenProvider: { nil }
        )

        let result = try syncSync(coordinator)
        guard case .success(let change) = result else { return XCTFail("no token must report success/no-op, not failure") }
        XCTAssertTrue(change.insertedIds.isEmpty && change.updatedIds.isEmpty && change.removedIds.isEmpty)
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 0)
    }

    // MARK: - Identity changes

    func testCooldownIsPerOwner() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-per-owner")
        var owner = MessageOwner(kind: .userId, id: "alice-\(name)")
        var config = HightouchMessagesConfig()
        config.foregroundSyncCooldown = 3600
        let coordinator = makeCoordinator(analytics: analytics, store: store, config: config, ownerProvider: { _ in owner })

        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["m1"]))
        _ = try syncSync(coordinator, force: false)
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 1)

        owner = MessageOwner(kind: .userId, id: "bob-\(name)")
        _ = try syncSync(coordinator, force: false)
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 2, "a new owner must sync despite the previous owner's cooldown")

        _ = try syncSync(coordinator, force: false)
        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 2, "the same owner stays rate-limited")
    }

    func testSyncForADifferentOwnerWhileOneIsInFlightRunsAfterIt() throws {
        let store = try makeStore()
        let analytics = makeAnalytics(writeKey: "\(name)-follow-up")
        let alice = MessageOwner(kind: .userId, id: "alice-\(name)")
        let bob = MessageOwner(kind: .userId, id: "bob-\(name)")
        var resolutions = 0
        let coordinator = makeCoordinator(analytics: analytics, store: store, ownerProvider: { _ in
            resolutions += 1
            return resolutions == 1 ? alice : bob
        })
        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["a1"]))
        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody(["b1"]))

        let first = expectation(description: "alice")
        let second = expectation(description: "bob")
        coordinator.sync(force: true) { _ in first.fulfill() }
        coordinator.sync(force: true) { _ in second.fulfill() }
        wait(for: [first, second], timeout: 5)

        XCTAssertEqual(StubMessagesURLProtocol.requestCount, 2)
        XCTAssertEqual(store.messages(matching: HightouchMessageQuery(), owner: bob).map { $0.messageId }, ["b1"])
    }

    // MARK: - MessagesHTTPClient request shape

    private func fetch(
        with client: MessagesHTTPClient,
        owner: MessageOwner = MessageOwner(kind: .userId, id: "alice"),
        deviceToken: String = MessagesSync_Tests.deviceToken
    ) throws -> URLRequest {
        StubMessagesURLProtocol.enqueue(status: 200, body: try messagesBody([]))
        let completed = expectation(description: "fetch")
        client.fetchMessages(owner: owner, deviceToken: deviceToken) { _ in completed.fulfill() }
        wait(for: [completed], timeout: 5)
        return try XCTUnwrap(StubMessagesURLProtocol.capturedRequests.last)
    }

    // MARK: - versionHash snapshot
    func testDefaultRequestIsAGetToTheGatewayPath() throws {
        let analytics = makeAnalytics(writeKey: "\(name)-default")
        let client = MessagesHTTPClient(analytics: analytics, config: HightouchMessagesConfig(), protocolClasses: [StubMessagesURLProtocol.self])

        let request = try fetch(with: client)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.hightouch.com/v1/inapp/messages")
        XCTAssertNil(StubMessagesURLProtocol.capturedBodies.last ?? nil, "a GET must carry no body")
    }

    /// Stands in for Xcode's model diff. Recompute deliberately on a real schema change and bump modelVersion.
    func testCredentialsAndIdentityTravelInGatewayHeaders() throws {
        let writeKey = "wk-secret-\(UUID().uuidString)"
        let analytics = makeAnalytics(writeKey: writeKey)
        let client = MessagesHTTPClient(analytics: analytics, config: HightouchMessagesConfig(), protocolClasses: [StubMessagesURLProtocol.self])

        let request = try fetch(with: client, owner: MessageOwner(kind: .userId, id: "alice@example.com"), deviceToken: "abc123")
        let basic = Data("\(writeKey):".utf8).base64EncodedString()
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic \(basic)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-hightouch-user-id"), "alice@example.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-hightouch-device-token"), "abc123")

        let urlString = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertFalse(urlString.contains(writeKey), "the write key must never appear in the URL")
        XCTAssertFalse(urlString.contains("alice"), "the user id must never appear in the URL")
        XCTAssertNil(request.url?.query)
    }

    func testRequestFactoryRunsAfterTheSDKHeaders() throws {
        let analytics = makeAnalytics(writeKey: "\(name)-factory")
        let client = MessagesHTTPClient(
            analytics: analytics,
            config: HightouchMessagesConfig(),
            protocolClasses: [StubMessagesURLProtocol.self],
            requestFactory: { request in
                var request = request
                request.setValue("override-user", forHTTPHeaderField: "x-hightouch-user-id")
                return request
            }
        )

        let request = try fetch(with: client)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-hightouch-user-id"), "override-user")
    }

    func testLocalhostHostProducesPlainHTTP() throws {
        let analytics = makeAnalytics(writeKey: "\(name)-14")
        var config = HightouchMessagesConfig()
        config.messagesHost = "localhost:8080"
        let client = MessagesHTTPClient(analytics: analytics, config: config, protocolClasses: [StubMessagesURLProtocol.self])

        let request = try fetch(with: client)
        XCTAssertEqual(request.url?.scheme, "http")
        XCTAssertEqual(request.url?.host, "localhost")
        XCTAssertEqual(request.url?.path, "/v1/inapp/messages")
    }
}
#endif
