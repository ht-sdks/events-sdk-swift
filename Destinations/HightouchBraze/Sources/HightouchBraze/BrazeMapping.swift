//
//  BrazeMapping.swift
//  HightouchBraze
//

import Foundation
import Hightouch

extension BrazeDestination {
    static let reservedTraitKeys: Set<String> = [
        "firstName", "first_name", "$FirstName",
        "lastName", "last_name", "$LastName",
        "email", "Email",
        "phone", "$Mobile",
        "gender", "$Gender",
        "birthday", "dob", "age", "$Age",
        "address", "home_city", "$City", "country", "$Country", "$Zip",
        "email_subscribe", "push_subscribe",
    ]
    static let bundledPurchaseName = "eCommerce - purchase"
    static let productFieldNames = [
        "name": "Name", "brand": "Brand", "category": "Category",
        "variant": "Variant", "position": "Position", "coupon": "Coupon Code",
    ]
    static let bundledProductFieldNames = productFieldNames.merging(["sku": "Id", "price": "Price", "quantity": "Quantity"]) { $1 }

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
        add(string("firstName", "first_name", "$FirstName"), BrazeUserUpdate.firstName)
        add(string("lastName", "last_name", "$LastName"), BrazeUserUpdate.lastName)
        add(string("email", "Email"), BrazeUserUpdate.email)
        add(string("phone", "$Mobile"), BrazeUserUpdate.phoneNumber)
        if let value = string("gender", "$Gender") {
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
        } else if let age = (traits["age"] ?? traits["$Age"])?.intValue {
            let year = Calendar.current.component(.year, from: Date()) - age
            if let date = DateComponents(calendar: .current, year: year, month: 1, day: 1).date {
                updates.append(.dateOfBirth(date))
            }
        }
        add(address["city"].flatMap(Self.scalarString) ?? string("home_city", "$City"), BrazeUserUpdate.homeCity)
        add(address["country"].flatMap(Self.scalarString) ?? string("country", "$Country"), BrazeUserUpdate.country)
        add(address["postalCode"].flatMap(Self.scalarString) ?? string("$Zip")) { .customAttribute("Zip", .string($0)) }
        for (key, makeUpdate) in [("email_subscribe", BrazeUserUpdate.emailSubscription), ("push_subscribe", BrazeUserUpdate.pushSubscription)] {
            guard let value = string(key) else { continue }
            if let state = Self.subscriptionState(from: value) {
                updates.append(makeUpdate(state))
            } else {
                log("Dropped \(key) value \"\(value)\"; expected opted_in, subscribed, or unsubscribed.")
            }
        }

        for (key, value) in traits.sorted(by: { $0.key < $1.key }) where !Self.reservedTraitKeys.contains(key) {
            let strippedKey = Self.stripDollars(key)
            guard !strippedKey.isEmpty else { continue }
            updates.append(.customAttribute(strippedKey, attributeValue(value)))
        }
        return updates
    }

    private func attributeValue(_ value: JSON) -> BrazeAttributeValue? {
        let stringify = options.stringifyAttributeValues
        switch value {
        case .null:
            return nil
        case .string(let string):
            return .string(string)
        case .bool(let bool):
            return stringify ? .string(String(bool)) : .bool(bool)
        case .number(let number):
            if stringify {
                return .string(number.description)
            }
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

    // Only the date portion is used, in the local calendar like mParticle's kit, so a UTC timestamp can't shift the birthday by a day.
    static func dateOfBirth(from value: String) -> Date? {
        guard value.count == 10 || value.dropFirst(10).first == "T" else { return nil }
        let parts = value.prefix(10).split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2] else { return nil }
        let components = DateComponents(calendar: .current, year: year, month: month, day: day)
        return components.isValidDate ? components.date : nil
    }

    // MARK: - Track and screen

    func forwardTrack(_ event: TrackEvent, to client: BrazeClient) {
        let name = Self.stripDollars(event.event)
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

        if isPurchase(event, name: name, properties: properties) {
            logPurchases(name: name, properties: properties, to: client)
        } else {
            client.logCustomEvent(name: name, properties: eventProperties(properties).nonEmpty)
        }
    }

    private func isPurchase(_ event: TrackEvent, name: String, properties: [String: JSON]) -> Bool {
        if let isPurchaseEvent = options.isPurchaseEvent {
            return isPurchaseEvent(event)
        }
        let revenue = Self.decimal(properties["revenue"])
        return options.purchaseEventNames.contains(name) || (options.logPurchaseWhenRevenuePresent && revenue != nil && revenue != 0)
    }

    func forwardScreen(_ event: ScreenEvent, to client: BrazeClient) {
        guard let name = event.name.map(Self.stripDollars), !name.isEmpty else { return }
        var properties = [String: JSON]()
        if case .object(let value)? = event.properties {
            properties = value
        }
        client.logCustomEvent(name: name, properties: eventProperties(properties).nonEmpty)
    }

    private func logPurchases(name: String, properties: [String: JSON], to client: BrazeClient) {
        var currency = "USD"
        if case .string(let value)? = properties["currency"], value.count == 3 {
            currency = value
        }
        let total = (Self.decimal(properties["revenue"]) ?? Self.decimal(properties["total"])).map(Self.double) ?? 0
        var order = properties
        order["products"] = nil
        order["currency"] = nil
        if let orderId = properties["order_id"] {
            order["Transaction Id"] = orderId
        }
        var products = [[String: JSON]]()
        if case .array(let items)? = properties["products"] {
            products = items.compactMap { item in
                guard case .object(let product) = item else { return nil }
                return product
            }
        }

        if options.bundleCommerceEvents {
            var bundled = eventProperties(order)
            if !products.isEmpty {
                bundled["products"] = products.map { eventProperties(Self.bundledProduct($0)) }
            }
            client.logPurchase(productId: Self.bundledPurchaseName, currency: currency, price: total, quantity: 1, properties: bundled.nonEmpty)
            return
        }

        guard !products.isEmpty else {
            client.logPurchase(productId: name, currency: currency, price: total, quantity: 1, properties: eventProperties(order).nonEmpty)
            return
        }

        for product in products {
            let idKey = options.purchaseProductIdentifier == .name
                ? "name"
                : ["sku", "product_id"].first { product[$0].flatMap(Self.scalarString)?.isEmpty == false }
            guard let idKey = idKey, let productId = product[idKey].flatMap(Self.scalarString), !productId.isEmpty else {
                log("Dropped a product from \(name) with no \(options.purchaseProductIdentifier == .name ? "name" : "sku or product_id").")
                continue
            }
            var fields = order
            for (key, value) in product {
                switch key {
                case "sku", "price", "quantity", "currency":
                    continue
                case "product_id" where idKey == "product_id":
                    continue
                default:
                    fields[Self.productFieldNames[key] ?? key] = value
                }
            }
            let price = Self.decimal(product["price"]).map(Self.double) ?? 0
            let quantity = product["quantity"]?.intValue ?? 1
            client.logPurchase(productId: productId, currency: currency, price: price, quantity: quantity, properties: eventProperties(fields).nonEmpty)
        }
    }

    static func bundledProduct(_ product: [String: JSON]) -> [String: JSON] {
        var result = [String: JSON]()
        for (key, value) in product {
            result[bundledProductFieldNames[key] ?? key] = value
        }
        if let price = decimal(product["price"]) {
            result["Total Product Amount"] = .number(price * (decimal(product["quantity"]) ?? 1))
        }
        return result
    }

    // MARK: - Values

    func eventProperties(_ properties: [String: JSON]) -> [String: Any] {
        var result = [String: Any]()
        for (key, value) in properties {
            let strippedKey = Self.stripDollars(key)
            guard !strippedKey.isEmpty, let converted = Self.propertyValue(value, stringify: options.stringifyAttributeValues) else { continue }
            result[strippedKey] = converted
        }
        return result
    }

    static func propertyValue(_ value: JSON, stringify: Bool) -> Any? {
        switch value {
        case .null:
            return nil
        case _ where stringify:
            return scalarString(value) ?? jsonString(value)
        case .string(let string):
            return string
        case .bool(let bool):
            return bool
        case .number(let number):
            return integer(number).map { $0 as Any } ?? double(number)
        case .array(let items):
            return items.compactMap { propertyValue($0, stringify: false) }
        case .object(let object):
            return object.compactMapValues { propertyValue($0, stringify: false) }
        }
    }

    static func stripDollars(_ key: String) -> String {
        return String(key.drop { $0 == "$" })
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
