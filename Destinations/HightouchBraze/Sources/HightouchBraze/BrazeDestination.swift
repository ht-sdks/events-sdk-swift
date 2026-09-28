//
//  BrazeDestination.swift
//  HightouchBraze
//

import Foundation
import Hightouch

/**
 Forwards Hightouch events to the Braze Swift SDK on the device, so Braze can evaluate in-app message
 triggers and Content Cards in real time. The destination only forwards data; display is up to your app
 through the exposed `braze` instance.
 */
public final class BrazeDestination: DestinationPlugin {
    public struct Options {
        public enum PurchaseProductIdentifier {
            /// `product.sku`, falling back to `product.product_id`.
            case sku
            /// `product.name`.
            case name
        }

        public var purchaseProductIdentifier: PurchaseProductIdentifier
        /// Log one `eCommerce - purchase` per `Order Completed` instead of one purchase per product.
        public var bundleCommerceEvents: Bool
        /// Forward `screen` calls as Braze custom events.
        public var forwardScreenViews: Bool
        /// Treat any `track` call with a non-zero `revenue` property as a purchase.
        public var logPurchaseWhenRevenuePresent: Bool
        /// Send user attribute and event property values as strings.
        public var stringifyAttributeValues: Bool

        public init(purchaseProductIdentifier: PurchaseProductIdentifier = .sku,
                    bundleCommerceEvents: Bool = false,
                    forwardScreenViews: Bool = false,
                    logPurchaseWhenRevenuePresent: Bool = false,
                    stringifyAttributeValues: Bool = false) {
            self.purchaseProductIdentifier = purchaseProductIdentifier
            self.bundleCommerceEvents = bundleCommerceEvents
            self.forwardScreenViews = forwardScreenViews
            self.logPurchaseWhenRevenuePresent = logPurchaseWhenRevenuePresent
            self.stringifyAttributeValues = stringifyAttributeValues
        }
    }

    struct UserState: Codable, Equatable {
        var userId: String?
        var attributes: [String: String] = [:]
    }

    static let maxPendingCount = 1000
    static let userStateKey = "com.hightouch.braze.userState"

    public let type = PluginType.destination
    public let key = "Appboy"
    public let timeline = Timeline()
    public weak var analytics: Analytics? = nil

    let options: Options
    private let userDefaults: UserDefaults
    // Recursive so an event tracked re-entrantly from inside a Braze call can't deadlock the host app.
    private let lock = NSRecursiveLock()
    private var client: BrazeClient?
    private var pending = [(BrazeClient) -> Void]()
    private var readyCallbacks = [(BrazeClient) -> Void]()
    private(set) var userState: UserState

    /// Creates the destination without a Braze instance. Events are queued until you call `setBraze(_:)`.
    public init(options: Options = Options()) {
        self.options = options
        self.userDefaults = .standard
        self.userState = Self.loadUserState(from: .standard)
    }

    init(options: Options, userDefaults: UserDefaults) {
        self.options = options
        self.userDefaults = userDefaults
        self.userState = Self.loadUserState(from: userDefaults)
    }

    public func update(settings: Settings, type: UpdateType) {
        // Braze is configured in code, so the Hightouch settings endpoint never lists this destination; without this the core would skip it.
        analytics?.manuallyEnableDestination(plugin: self)
    }

    public func identify(event: IdentifyEvent) -> IdentifyEvent? {
        guard isEnabled(for: event) else { return event }
        perform { self.forwardIdentify(event, to: $0) }
        return event
    }

    public func track(event: TrackEvent) -> TrackEvent? {
        guard isEnabled(for: event) else { return event }
        perform { self.forwardTrack(event, to: $0) }
        return event
    }

    public func screen(event: ScreenEvent) -> ScreenEvent? {
        guard options.forwardScreenViews, isEnabled(for: event) else { return event }
        perform { self.forwardScreen(event, to: $0) }
        return event
    }

    public func flush() {
        perform { $0.requestImmediateDataFlush() }
    }

    public func reset() {
        perform { _ in self.saveUserState(UserState()) }
    }
}

// MARK: - Readiness

extension BrazeDestination {
    var currentClient: BrazeClient? {
        lock.lock()
        defer { lock.unlock() }
        return client
    }

    func start(client: BrazeClient) {
        lock.lock()
        self.client = client
        let replay = pending
        pending.removeAll()
        replay.forEach { $0(client) }
        let callbacks = readyCallbacks
        readyCallbacks.removeAll()
        lock.unlock()
        callbacks.forEach { $0(client) }
    }

    func onClientReady(_ callback: @escaping (BrazeClient) -> Void) {
        lock.lock()
        guard let client = client else {
            readyCallbacks.append(callback)
            lock.unlock()
            return
        }
        lock.unlock()
        callback(client)
    }

    // Everything runs under the lock so Braze calls and the attribute cache stay in event order across threads.
    private func perform(_ work: @escaping (BrazeClient) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let client = client else {
            if pending.count >= Self.maxPendingCount {
                pending.removeFirst()
            }
            pending.append(work)
            return
        }
        work(client)
    }

    private func isEnabled(for event: RawEvent) -> Bool {
        let integrations = event.integrations?.dictionaryValue
        let own = integrations?[key] as? Bool
        if own == false { return false }
        return !(integrations?["All"] as? Bool == false && own != true)
    }
}

// MARK: - Identity

extension BrazeDestination {
    private func forwardIdentify(_ event: IdentifyEvent, to client: BrazeClient) {
        var state = userState
        if let userId = event.userId, !userId.isEmpty, userId != state.userId {
            client.changeUser(userId: userId)
            state = UserState(userId: userId)
        }
        for update in userUpdates(from: event.traits) where state.attributes[update.cacheKey] != update.cacheValue {
            client.update(update)
            state.attributes[update.cacheKey] = update.cacheValue
        }
        if state != userState {
            saveUserState(state)
        }
    }

    private static func loadUserState(from userDefaults: UserDefaults) -> UserState {
        guard let data = userDefaults.data(forKey: userStateKey),
              let state = try? JSONDecoder().decode(UserState.self, from: data) else { return UserState() }
        return state
    }

    private func saveUserState(_ state: UserState) {
        userState = state
        if let data = try? JSONEncoder().encode(state) {
            userDefaults.set(data, forKey: Self.userStateKey)
        }
    }

    func log(_ message: String) {
        analytics?.log(message: "BrazeDestination: \(message)")
    }
}
