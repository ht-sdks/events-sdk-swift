//
//  BrazeMapping.swift
//  HightouchBraze
//

import Foundation
import Hightouch

extension BrazeDestination {
    static let reservedTraitKeys: Set<String> = [
        "firstName", "first_name",
        "lastName", "last_name",
        "email",
        "phone",
        "gender",
        "birthday", "dob",
        "address", "home_city", "country",
        "email_subscribe", "push_subscribe",
    ]

    // MARK: - Identify

    func userUpdates(from traits: JSON?) -> [BrazeUserUpdate] {
        guard case .object(let traits)? = traits else { return [] }
        var address = [String: JSON]()
        if case .object(let value)? = traits["address"] {
            address = value
        }
        func string(_ keys: String...) -> String? {
            return keys.lazy.compactMap { traits[$0].flatMap(Self.scalarString) }.first
        }

        var updates = [BrazeUserUpdate]()
        func add(_ value: String?, _ makeUpdate: (String) -> BrazeUserUpdate) {
            if let value = value {
                updates.append(makeUpdate(value))
            }
        }
        add(string("firstName", "first_name"), BrazeUserUpdate.firstName)
        add(string("lastName", "last_name"), BrazeUserUpdate.lastName)
        add(string("email"), BrazeUserUpdate.email)
        add(string("phone"), BrazeUserUpdate.phoneNumber)
        if let value = string("gender") {
            if let gender = Self.gender(from: value) {
                updates.append(.gender(gender))
            } else {
                log("Dropped unrecognized gender \"\(value)\".")
            }
        }
        if let value = string("birthday", "dob") {
            if let date = Self.dateOfBirth(from: value) {
                updates.append(.dateOfBirth(date))
            } else {
                log("Dropped birthday \"\(value)\"; expected an ISO 8601 or yyyy-MM-dd date.")
            }
        }
        add(address["city"].flatMap(Self.scalarString) ?? string("home_city"), BrazeUserUpdate.homeCity)
        add(address["country"].flatMap(Self.scalarString) ?? string("country"), BrazeUserUpdate.country)
        for (key, value) in address.sorted(by: { $0.key < $1.key }) where key != "city" && key != "country" {
            updates.append(.customAttribute(key, attributeValue(value)))
        }
        for (key, makeUpdate) in [("email_subscribe", BrazeUserUpdate.emailSubscription), ("push_subscribe", BrazeUserUpdate.pushSubscription)] {
            guard let value = string(key) else { continue }
            if let state = Self.subscriptionState(from: value) {
                updates.append(makeUpdate(state))
            } else {
                log("Dropped \(key) value \"\(value)\"; expected opted_in, subscribed, or unsubscribed.")
            }
        }

        for (key, value) in traits.sorted(by: { $0.key < $1.key }) where !Self.reservedTraitKeys.contains(key) && !key.isEmpty {
            updates.append(.customAttribute(key, attributeValue(value)))
        }
        return updates
    }

    private func attributeValue(_ value: JSON) -> BrazeAttributeValue? {
        switch value {
        case .null:
            return nil
        case .string(let string):
            return .string(string)
        case .bool(let bool):
            return .bool(bool)
        case .number(let number):
            return Self.integer(number).map { .int($0) } ?? .double(NSDecimalNumber(decimal: number).doubleValue)
        case .array(let items):
            return .stringArray(items.compactMap { item in
                if case .null = item { return nil }
                return Self.scalarString(item) ?? Self.jsonString(item)
            })
        case .object:
            return .string(Self.jsonString(value))
        }
    }

    static func gender(from value: String) -> BrazeGender? {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "m", "male": return .male
        case "f", "female": return .female
        case "o", "other": return .other
        case "u", "unknown": return .unknown
        case "n", "not_applicable", "not applicable": return .notApplicable
        case "p", "prefer_not_to_say", "prefer not to say": return .preferNotToSay
        default: return nil
        }
    }

    static func subscriptionState(from value: String) -> BrazeSubscriptionState? {
        switch value {
        case "opted_in": return .optedIn
        case "subscribed": return .subscribed
        case "unsubscribed": return .unsubscribed
        default: return nil
        }
    }

    // Only the date portion is used, in the local calendar, so a UTC timestamp can't shift the birthday by a day.
    static func dateOfBirth(from value: String) -> Date? {
        guard value.count == 10 || value.dropFirst(10).first == "T" else { return nil }
        let parts = value.prefix(10).split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2] else { return nil }
        let components = DateComponents(calendar: .current, year: year, month: month, day: day)
        return components.isValidDate ? components.date : nil
    }

    // MARK: - Track and screen

    func forwardTrack(_ event: TrackEvent, to client: BrazeClient) {
        let name = event.event
        guard !name.isEmpty else {
            log("Dropped track call with an empty event name.")
            return
        }
        var properties = [String: JSON]()
        if case .object(let value)? = event.properties {
            properties = value
        }

        if name == "Install Attributed", case .object(let campaign)? = properties["campaign"] {
            func field(_ key: String) -> String { return campaign[key].flatMap(Self.scalarString) ?? "" }
            client.setAttributionData(network: field("source"), campaign: field("name"), adGroup: field("ad_group"), creative: field("ad_creative"))
        }

        let isPurchase: Bool
        switch options.purchaseDetection {
        case .eventNames(let names): isPurchase = names.contains(name)
        case .matcher(let isPurchaseEvent): isPurchase = isPurchaseEvent(event)
        }
        if isPurchase {
            logPurchases(event, properties: properties, to: client)
        } else {
            client.logCustomEvent(name: name, properties: eventProperties(properties).nonEmpty)
        }
    }

    func forwardScreen(_ event: ScreenEvent, to client: BrazeClient) {
        guard let name = event.name, !name.isEmpty else { return }
        var properties = [String: JSON]()
        if case .object(let value)? = event.properties {
            properties = value
        }
        client.logCustomEvent(name: name, properties: eventProperties(properties).nonEmpty)
    }

    private func logPurchases(_ event: TrackEvent, properties: [String: JSON], to client: BrazeClient) {
        var currency = "USD"
        if case .string(let value)? = properties["currency"], value.count == 3 {
            currency = value
        }
        let order = eventProperties(properties)
        var products = [[String: JSON]]()
        if case .array(let items)? = properties["products"] {
            products = items.compactMap { item in
                guard case .object(let product) = item else { return nil }
                return product
            }
        }

        guard case .perProduct(let identifier) = options.purchaseGrouping, !products.isEmpty else {
            let total = (Self.decimal(properties["revenue"]) ?? Self.decimal(properties["total"])).map(Self.double) ?? 0
            let purchase = BrazePurchase(productId: event.event, price: total, currency: currency, quantity: 1, properties: eventProperties(properties))
            logPurchase(purchase, context: PurchaseContext(event: event, order: order, product: nil), to: client)
            return
        }

        let idKeys = identifier == .name ? ["name"] : ["sku", "product_id", "name"]
        var orderFields = properties
        orderFields["products"] = nil
        for product in products {
            let productId = idKeys.lazy.compactMap({ product[$0].flatMap(Self.scalarString) }).first(where: { !$0.isEmpty }) ?? ""
            let fields = orderFields.merging(product.filter { $0.key != "price" && $0.key != "quantity" }) { $1 }
            let price = Self.decimal(product["price"]).map(Self.double) ?? 0
            let quantity = product["quantity"]?.intValue ?? 1
            let purchase = BrazePurchase(productId: productId, price: price, currency: currency, quantity: quantity, properties: eventProperties(fields))
            logPurchase(purchase, context: PurchaseContext(event: event, order: order, product: eventProperties(product)), to: client)
        }
    }

    private func logPurchase(_ purchase: BrazePurchase, context: PurchaseContext, to client: BrazeClient) {
        var purchase = purchase
        if let transformPurchase = options.transformPurchase {
            guard let transformed = transformPurchase(purchase, context) else { return }
            purchase = transformed
        }
        guard !purchase.productId.isEmpty else {
            log("Dropped a purchase from \(context.event.event) with an empty productId.")
            return
        }
        client.logPurchase(productId: purchase.productId, currency: purchase.currency, price: purchase.price, quantity: purchase.quantity, properties: purchase.properties.nonEmpty)
    }

    // MARK: - Values

    func eventProperties(_ properties: [String: JSON]) -> [String: Any] {
        return properties.compactMapValues { Self.propertyValue($0) }
    }

    static func propertyValue(_ value: JSON) -> Any? {
        switch value {
        case .null:
            return nil
        case .string(let string):
            return string
        case .bool(let bool):
            return bool
        case .number(let number):
            return integer(number).map { $0 as Any } ?? double(number)
        case .array(let items):
            return items.compactMap { propertyValue($0) }
        case .object(let object):
            return object.compactMapValues { propertyValue($0) }
        }
    }

    static func scalarString(_ value: JSON) -> String? {
        switch value {
        case .string(let string): return string
        case .number(let number): return number.description
        case .bool(let bool): return String(bool)
        default: return nil
        }
    }

    static func jsonString(_ value: JSON) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func decimal(_ value: JSON?) -> Decimal? {
        switch value {
        case .number(let number)?: return number
        case .string(let string)?: return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        default: return nil
        }
    }

    static func double(_ value: Decimal) -> Double {
        return NSDecimalNumber(decimal: value).doubleValue
    }

    static func integer(_ value: Decimal) -> Int? {
        let asDouble = double(value)
        return asDouble.rounded() == asDouble ? Int(exactly: asDouble) : nil
    }
}

private extension Dictionary where Key == String, Value == Any {
    var nonEmpty: [String: Any]? {
        return isEmpty ? nil : self
    }
}
