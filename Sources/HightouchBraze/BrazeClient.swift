//
//  BrazeClient.swift
//  HightouchBraze
//

import Foundation

internal enum BrazeGender: Equatable {
    case male, female, other, unknown, notApplicable, preferNotToSay
}

internal enum BrazeSubscriptionState: Equatable {
    case optedIn, subscribed, unsubscribed
}

internal enum BrazeAttributeValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringArray([String])
}

internal enum BrazeUserUpdate: Equatable {
    case firstName(String)
    case lastName(String)
    case email(String)
    case phoneNumber(String)
    case gender(BrazeGender)
    case dateOfBirth(Date)
    case homeCity(String)
    case country(String)
    case emailSubscription(BrazeSubscriptionState)
    case pushSubscription(BrazeSubscriptionState)
    /// A `nil` value unsets the attribute.
    case customAttribute(String, BrazeAttributeValue?)

    var cacheKey: String {
        if case .customAttribute(let key, _) = self {
            return "custom.\(key)"
        }
        return Mirror(reflecting: self).children.first?.label ?? String(describing: self)
    }

    var cacheValue: String {
        return String(describing: self)
    }
}

/// The subset of the Braze SDK the destination drives, so the mapping can be tested without BrazeKit.
internal protocol BrazeClient: AnyObject {
    func changeUser(userId: String)
    func update(_ update: BrazeUserUpdate)
    func setAttributionData(network: String, campaign: String, adGroup: String, creative: String)
    func logCustomEvent(name: String, properties: [String: Any]?)
    func logPurchase(productId: String, currency: String, price: Double, quantity: Int, properties: [String: Any]?)
    func requestImmediateDataFlush()
}

#if canImport(BrazeKit)
import BrazeKit

internal final class BrazeKitClient: BrazeClient {
    let braze: Braze

    init(braze: Braze) {
        self.braze = braze
    }

    func changeUser(userId: String) {
        braze.changeUser(userId: userId)
    }

    func update(_ update: BrazeUserUpdate) {
        let user = braze.user
        switch update {
        case .firstName(let value): user.set(firstName: value)
        case .lastName(let value): user.set(lastName: value)
        case .email(let value): user.set(email: value)
        case .phoneNumber(let value): user.set(phoneNumber: value)
        case .gender(let value): user.set(gender: value.braze)
        case .dateOfBirth(let value): user.set(dateOfBirth: value)
        case .homeCity(let value): user.set(homeCity: value)
        case .country(let value): user.set(country: value)
        case .emailSubscription(let value): user.set(emailSubscriptionState: value.braze)
        case .pushSubscription(let value): user.set(pushNotificationSubscriptionState: value.braze)
        case .customAttribute(let key, nil): user.unsetCustomAttribute(key: key)
        case .customAttribute(let key, .string(let value)?): user.setCustomAttribute(key: key, value: value)
        case .customAttribute(let key, .int(let value)?): user.setCustomAttribute(key: key, value: value)
        case .customAttribute(let key, .double(let value)?): user.setCustomAttribute(key: key, value: value)
        case .customAttribute(let key, .bool(let value)?): user.setCustomAttribute(key: key, value: value)
        case .customAttribute(let key, .stringArray(let value)?): user.setCustomAttribute(key: key, array: value)
        }
    }

    func setAttributionData(network: String, campaign: String, adGroup: String, creative: String) {
        braze.user.set(attributionData: Braze.User.AttributionData(network: network, campaign: campaign, adGroup: adGroup, creative: creative))
    }

    func logCustomEvent(name: String, properties: [String: Any]?) {
        braze.logCustomEvent(name: name, properties: properties)
    }

    func logPurchase(productId: String, currency: String, price: Double, quantity: Int, properties: [String: Any]?) {
        braze.logPurchase(productId: productId, currency: currency, price: price, quantity: quantity, properties: properties)
    }

    func requestImmediateDataFlush() {
        braze.requestImmediateDataFlush()
    }
}

private extension BrazeGender {
    var braze: Braze.User.Gender {
        switch self {
        case .male: return .male
        case .female: return .female
        case .other: return .other
        case .unknown: return .unknown
        case .notApplicable: return .notApplicable
        case .preferNotToSay: return .preferNotToSay
        }
    }
}

private extension BrazeSubscriptionState {
    var braze: Braze.User.SubscriptionState {
        switch self {
        case .optedIn: return .optedIn
        case .subscribed: return .subscribed
        case .unsubscribed: return .unsubscribed
        }
    }
}

extension BrazeDestination {
    /// Creates the destination and initializes Braze with the given API key and SDK endpoint.
    ///
    /// - Parameter configure: Customize the `Braze.Configuration` (for example log level or session timeout) before Braze is initialized.
    public convenience init(apiKey: String, endpoint: String, options: Options = Options(), configure: ((Braze.Configuration) -> Void)? = nil) {
        let configuration = Braze.Configuration(apiKey: apiKey, endpoint: endpoint)
        configure?(configuration)
        self.init(braze: Braze(configuration: configuration), options: options)
    }

    /// Creates the destination with a Braze instance your app already initialized. The destination doesn't initialize Braze.
    public convenience init(braze: Braze, options: Options = Options()) {
        self.init(options: options)
        setBraze(braze)
    }

    /// Supplies the Braze instance to a destination created with `init(options:)`. Events received before this call are replayed in order.
    public func setBraze(_ braze: Braze) {
        start(client: BrazeKitClient(braze: braze))
    }

    /// The Braze instance events are forwarded to, or `nil` until one is available. Use it for in-app message and Content Card UI.
    public var braze: Braze? {
        return (currentClient as? BrazeKitClient)?.braze
    }

    /// Calls `callback` once Braze is available: immediately if it already is, otherwise on the thread that calls `setBraze(_:)`.
    public func onReady(_ callback: @escaping (Braze) -> Void) {
        onClientReady { client in
            if let braze = (client as? BrazeKitClient)?.braze {
                callback(braze)
            }
        }
    }
}
#endif
