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
            /// `product.sku`, falling back to `product.product_id`, then `product.name`.
            case sku
            /// `product.name`.
            case name
        }

        public enum PurchaseDetection {
            /// `track` events with one of these names. Case-sensitive.
            case eventNames([String])
            /// `track` events for which the closure returns `true`.
            case matcher((TrackEvent) -> Bool)
        }

        /// Products require a finite price. Omitted quantities default to 1; supplied quantities must be integers from 1 to 100.
        /// Whole-order purchases require revenue (or total if revenue is absent); quantity also defaults to 1.
        /// Complete numeric strings and an explicit zero price are accepted.
        public enum PurchaseGrouping {
            /// One purchase per product. An event without products is logged as one purchase with the event name as its product ID.
            case perProduct(identifier: PurchaseProductIdentifier)
            /// One purchase per purchase event, with the event name as its product ID.
            case perOrder
        }

        /// Which `track` events are logged as purchases.
        public var purchaseDetection: PurchaseDetection
        /// How a purchase event is split into Braze purchases.
        public var purchaseGrouping: PurchaseGrouping
        /// Forward `screen` calls as Braze custom events.
        public var forwardScreenViews: Bool
        /// Fallback for missing or invalid purchase currencies. No implicit default.
        /// Must normalize to three ASCII letters; whitespace and case are normalized.
        /// Braze determines which currency codes it supports.
        public var defaultCurrency: String?
        /// Changes each purchase before it's logged. Return `nil` to skip the purchase.
        public var transformPurchase: ((BrazePurchase, PurchaseContext) -> BrazePurchase?)?

        public init(purchaseDetection: PurchaseDetection = .eventNames(["Order Completed", "Completed Order"]),
                    purchaseGrouping: PurchaseGrouping = .perProduct(identifier: .sku),
                    forwardScreenViews: Bool = false,
                    defaultCurrency: String? = nil,
                    transformPurchase: ((BrazePurchase, PurchaseContext) -> BrazePurchase?)? = nil) {
            self.purchaseDetection = purchaseDetection
            self.purchaseGrouping = purchaseGrouping
            self.forwardScreenViews = forwardScreenViews
            self.defaultCurrency = defaultCurrency
            self.transformPurchase = transformPurchase
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
    private let lock = NSLock()
    private var client: BrazeClient?
    private var pending = [(BrazeClient) -> Void]()
    private var isDraining = false
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
        perform { client in
            do {
                try self.forwardTrack(event, to: client)
            } catch {
                self.analytics?.reportInternalError(AnalyticsError.pluginError(error))
            }
        }
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

/// Purchase validation errors reported through `Configuration.errorHandler` as `AnalyticsError.pluginError`.
public enum BrazeDestinationError: Error, LocalizedError, Equatable {
    case invalidCurrency(String?)
    case invalidDefaultCurrency(String)
    case invalidPrice
    case invalidQuantity

    public var errorDescription: String? {
        switch self {
        case .invalidCurrency(let value):
            return "Braze purchase rejected: invalid or missing currency (\(value ?? "nil")). Send a three-letter currency code or configure defaultCurrency."
        case .invalidDefaultCurrency(let value):
            return "Braze purchase rejected: defaultCurrency (\(value)) must be a three-letter currency code."
        case .invalidPrice:
            return "Braze purchase rejected: price must be explicitly supplied as a finite number."
        case .invalidQuantity:
            return "Braze purchase rejected: quantity must be an integer from 1 to 100."
        }
    }
}

/// A purchase the destination is about to log with Braze's `logPurchase`.
public struct BrazePurchase {
    public var productId: String
    public var price: Double
    public var currency: String
    public var quantity: Int
    public var properties: [String: Any]

    public init(productId: String, price: Double, currency: String, quantity: Int, properties: [String: Any]) {
        self.productId = productId
        self.price = price
        self.currency = currency
        self.quantity = quantity
        self.properties = properties
    }
}

/// What a purchase passed to `transformPurchase` was built from.
public struct PurchaseContext {
    public let event: TrackEvent
    /// The event's properties.
    public let order: [String: Any]
    /// The product this purchase came from, or `nil` for a per-order purchase or an order without products.
    public let product: [String: Any]?
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
        pending.append(contentsOf: readyCallbacks)
        readyCallbacks.removeAll()
        drain()
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

    private func perform(_ work: @escaping (BrazeClient) -> Void) {
        lock.lock()
        let overflow = client == nil && pending.count >= Self.maxPendingCount
        if overflow {
            pending.removeFirst()
        }
        pending.append(work)
        drain()
        if overflow {
            log("Warning: pending queue reached \(Self.maxPendingCount) operations; dropped the oldest operation. Call setBraze(_:) to start forwarding queued events.")
        }
    }

    // Called with the lock held; always releases it. Only one caller drains Braze calls and
    // cache updates, so concurrent/reentrant calls can enqueue and return without reordering events.
    private func drain() {
        guard !isDraining, client != nil else {
            lock.unlock()
            return
        }
        isDraining = true
        while let client = client, !pending.isEmpty {
            let work = pending
            pending.removeAll()
            lock.unlock()
            // Customer callbacks may synchronously wait for another thread that calls analytics.
            work.forEach { $0(client) }
            lock.lock()
        }
        isDraining = false
        lock.unlock()
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
