//
//  BrazeDestination_Tests.swift
//  HightouchBraze-Tests
//

import XCTest
import Hightouch
@testable import HightouchBraze

final class FakeBrazeClient: BrazeClient {
    enum Call: Equatable {
        case changeUser(String)
        case update(BrazeUserUpdate)
        case attribution(String, String, String, String)
        case customEvent(String, NSDictionary?)
        case purchase(String, String, Double, Int, NSDictionary?)
        case flush
    }

    var calls = [Call]()
    let stateStorageKey: String?
    var userId: String?

    init(apiKey: String? = "test-key", endpoint: String? = "sdk.iad-01.braze.com", userId: String? = nil) {
        self.stateStorageKey = BrazeDestination.storageKey(apiKey: apiKey, endpoint: endpoint)
        self.userId = userId
    }

    func changeUser(userId: String) {
        self.userId = userId
        calls.append(.changeUser(userId))
    }
    func update(_ update: BrazeUserUpdate) { calls.append(.update(update)) }
    func setAttributionData(network: String, campaign: String, adGroup: String, creative: String) {
        calls.append(.attribution(network, campaign, adGroup, creative))
    }
    func logCustomEvent(name: String, properties: [String: Any]?) {
        calls.append(.customEvent(name, properties.map { NSDictionary(dictionary: $0) }))
    }
    func logPurchase(productId: String, currency: String, price: Double, quantity: Int, properties: [String: Any]?) {
        calls.append(.purchase(productId, currency, price, quantity, properties.map { NSDictionary(dictionary: $0) }))
    }
    func requestImmediateDataFlush() { calls.append(.flush) }
}

final class BrazeDestination_Tests: XCTestCase {
    var userDefaults: UserDefaults!
    var client: FakeBrazeClient!

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: "HightouchBraze-Tests")
        userDefaults = UserDefaults(suiteName: "HightouchBraze-Tests")
        client = FakeBrazeClient()
    }

    func makeDestination(_ options: BrazeDestination.Options = .init(), start: Bool = true) -> BrazeDestination {
        let destination = BrazeDestination(options: options, userDefaults: userDefaults)
        if start {
            destination.start(client: client)
        }
        return destination
    }

    func identify(_ destination: BrazeDestination, userId: String? = nil, _ traits: [String: Any] = [:]) {
        _ = destination.identify(event: IdentifyEvent(userId: userId, traits: try! JSON(traits)))
    }

    func track(_ destination: BrazeDestination, _ name: String, _ properties: [String: Any] = [:], integrations: [String: Any]? = nil) {
        var event = TrackEvent(event: name, properties: try! JSON(properties))
        event.integrations = try! JSON(nilOrObject: integrations)
        _ = destination.track(event: event)
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        return DateComponents(calendar: .current, year: year, month: month, day: day).date!
    }

    // MARK: - Identity

    func testChangeUserOnlyWhenUserIdChanges() {
        let destination = makeDestination()
        identify(destination, userId: "u1")
        identify(destination, userId: "u1")
        identify(destination, userId: "u2")
        XCTAssertEqual(client.calls, [.changeUser("u1"), .changeUser("u2")])
    }

    func testAnonymousIdentifyAppliesTraitsWithoutChangingUser() {
        let destination = makeDestination()
        identify(destination, ["email": "a@example.com"])
        XCTAssertEqual(client.calls, [.update(.email("a@example.com"))])
    }

    func testReservedTraits() {
        let destination = makeDestination()
        identify(destination, [
            "first_name": "Jane",
            "lastName": "Doe",
            "email": "jane@example.com",
            "phone": "555-0100",
            "gender": "Female",
            "birthday": "1990-05-12T08:00:00Z",
            "address": ["city": "Austin", "country": "US", "postalCode": "78701", "street": "1 Main"],
            "email_subscribe": "opted_in",
            "push_subscribe": "unsubscribed",
        ])
        XCTAssertEqual(client.calls, [
            .update(.firstName("Jane")),
            .update(.lastName("Doe")),
            .update(.email("jane@example.com")),
            .update(.phoneNumber("555-0100")),
            .update(.gender(.female)),
            .update(.dateOfBirth(date(1990, 5, 12))),
            .update(.homeCity("Austin")),
            .update(.country("US")),
            .update(.customAttribute("postalCode", .string("78701"))),
            .update(.customAttribute("street", .string("1 Main"))),
            .update(.emailSubscription(.optedIn)),
            .update(.pushSubscription(.unsubscribed)),
        ])
    }

    func testNullClearsStandardAttributesAndPreservesAliasPrecedence() {
        let destination = makeDestination()
        identify(destination, userId: "u1")
        client.calls.removeAll()
        let values: [String: Any] = [
            "firstName": "Ada", "lastName": "Lovelace", "email": "ada@example.com",
            "phone": "555-0100", "gender": "female", "birthday": "1990-05-12",
            "address": ["city": "London", "country": "GB"],
        ]
        identify(destination, values)
        let original = client.calls
        client.calls.removeAll()
        identify(destination)
        XCTAssertEqual(client.calls, [])
        let clears: [String: Any] = [
            "firstName": NSNull(), "first_name": "Ignored", "lastName": NSNull(), "last_name": "Ignored",
            "email": NSNull(), "phone": NSNull(), "gender": NSNull(),
            "birthday": NSNull(), "dob": "2000-01-01",
            "address": ["city": NSNull(), "country": NSNull()], "home_city": "Ignored", "country": "US",
        ]
        identify(destination, clears)
        XCTAssertEqual(client.calls, [
            .update(.firstName(nil)), .update(.lastName(nil)), .update(.email(nil)),
            .update(.phoneNumber(nil)), .update(.gender(nil)), .update(.dateOfBirth(nil)),
            .update(.homeCity(nil)), .update(.country(nil)),
        ])
        client.calls.removeAll()
        identify(makeDestination(), clears)
        XCTAssertEqual(client.calls, [])
        identify(destination, values)
        XCTAssertEqual(client.calls, original)
    }

    func testNullClearsAliasAttributes() {
        let destination = makeDestination()
        identify(destination, ["first_name": NSNull(), "last_name": NSNull(), "dob": NSNull(),
                               "home_city": NSNull(), "country": NSNull()])
        XCTAssertEqual(client.calls, [.update(.firstName(nil)), .update(.lastName(nil)),
                                      .update(.dateOfBirth(nil)), .update(.homeCity(nil)), .update(.country(nil))])
    }

    func testBrazeLocationNames() {
        let destination = makeDestination()
        identify(destination, ["home_city": "Austin", "country": "US"])
        XCTAssertEqual(client.calls, [.update(.homeCity("Austin")), .update(.country("US"))])
    }

    func testMParticleNamesAndAgeAreCustomAttributes() {
        let destination = makeDestination()
        identify(destination, ["$FirstName": "Jane", "Email": "jane@example.com", "$Zip": "78701", "age": 30])
        XCTAssertEqual(client.calls, [
            .update(.customAttribute("$FirstName", .string("Jane"))),
            .update(.customAttribute("$Zip", .string("78701"))),
            .update(.customAttribute("Email", .string("jane@example.com"))),
            .update(.customAttribute("age", .int(30))),
        ])
    }

    func testInvalidReservedValuesAreDropped() {
        let destination = makeDestination()
        identify(destination, ["gender": "robot", "birthday": "05/12/1990", "email_subscribe": "maybe"])
        XCTAssertEqual(client.calls, [])
    }

    func testCustomAttributes() {
        let destination = makeDestination()
        identify(destination, [
            "$plan": "pro",
            "count": 3,
            "ratio": 1.5,
            "active": true,
            "tags": ["a", 1, true],
            "prefs": ["b": 1, "a": "x"],
            "removed": NSNull(),
        ])
        XCTAssertEqual(client.calls, [
            .update(.customAttribute("$plan", .string("pro"))),
            .update(.customAttribute("active", .bool(true))),
            .update(.customAttribute("count", .int(3))),
            .update(.customAttribute("prefs", .string(#"{"a":"x","b":1}"#))),
            .update(.customAttribute("ratio", .double(1.5))),
            .update(.customAttribute("removed", nil)),
            .update(.customAttribute("tags", .stringArray(["a", "1", "true"]))),
        ])
    }

    func testExplicitStringValues() {
        let destination = makeDestination()
        identify(destination, ["count": "3", "active": "true"])
        track(destination, "Viewed", ["count": "3", "nested": #"{"a":1}"#])
        XCTAssertEqual(client.calls, [
            .update(.customAttribute("active", .string("true"))),
            .update(.customAttribute("count", .string("3"))),
            .customEvent("Viewed", ["count": "3", "nested": #"{"a":1}"#]),
        ])
    }

    // MARK: - Deduplication

    func testIdentifySendsOnlyChangedAttributes() {
        let destination = makeDestination()
        identify(destination, userId: "u1", ["email": "a@example.com", "plan": "pro"])
        client.calls.removeAll()
        identify(destination, userId: "u1", ["email": "a@example.com", "plan": "pro"])
        XCTAssertEqual(client.calls, [])
        identify(destination, userId: "u1", ["email": "a@example.com", "plan": "max"])
        XCTAssertEqual(client.calls, [.update(.customAttribute("plan", .string("max")))])
    }

    func testAttributeCachePersistsAcrossLaunches() {
        identify(makeDestination(), userId: "u1", ["plan": "pro"])
        client = FakeBrazeClient(userId: "u1")
        identify(makeDestination(), userId: "u1", ["plan": "pro"])
        XCTAssertEqual(client.calls, [])
    }

    func testCacheIsScopedToAPIKeyAndEndpoint() {
        identify(makeDestination(), userId: "u1", ["plan": "pro"])
        for nextClient in [FakeBrazeClient(apiKey: "other-key"),
                           FakeBrazeClient(endpoint: "sdk.fra-01.braze.eu")] {
            client = nextClient
            let destination = makeDestination()
            XCTAssertEqual(client.calls, [], "Do not restore another configuration's identity")
            identify(destination, userId: "u1", ["plan": "pro"])
            XCTAssertEqual(client.calls, [.changeUser("u1"), .update(.customAttribute("plan", .string("pro")))])
        }
    }

    func testAttachmentReconcilesIdentityBeforeQueuedEventsAndResendsTraits() {
        identify(makeDestination(), userId: "u1", ["plan": "pro"])
        for currentUser in [nil, "another-user"] as [String?] {
            client = FakeBrazeClient(userId: currentUser)
            let destination = makeDestination(start: false)
            track(destination, "Queued")
            identify(destination, userId: "u1", ["plan": "pro"])
            destination.start(client: client)
            XCTAssertEqual(client.calls, [
                .changeUser("u1"), .customEvent("Queued", nil),
                .update(.customAttribute("plan", .string("pro"))),
            ])
            identify(destination, userId: "u1", ["plan": "pro"])
            XCTAssertEqual(client.calls.count, 3)
        }
    }

    func testLegacyGlobalCacheIsIgnored() throws {
        let oldState = BrazeDestination.UserState(userId: "u1", attributes: ["custom.plan": "old-value"])
        userDefaults.set(try JSONEncoder().encode(oldState), forKey: BrazeDestination.userStateKey)
        let destination = makeDestination()
        XCTAssertEqual(client.calls, [])
        identify(destination, userId: "u1", ["plan": "pro"])
        XCTAssertEqual(client.calls, [.changeUser("u1"), .update(.customAttribute("plan", .string("pro")))])
    }

    func testMissingConfigurationDoesNotReusePersistedState() {
        for _ in 0..<2 {
            client = FakeBrazeClient(apiKey: nil)
            identify(makeDestination(), userId: "u1", ["plan": "pro"])
            XCTAssertEqual(client.calls, [.changeUser("u1"), .update(.customAttribute("plan", .string("pro")))])
        }
    }

    func testAnonymousAttributesAreResentToFreshClient() {
        identify(makeDestination(), ["plan": "pro"])
        client = FakeBrazeClient()
        identify(makeDestination(), ["plan": "pro"])
        XCTAssertEqual(client.calls, [.update(.customAttribute("plan", .string("pro")))])
    }

    func testReplacingClientAndResetKeepConfigurationCachesSeparate() {
        let destination = makeDestination()
        identify(destination, userId: "u1", ["plan": "pro"])
        let otherClient = FakeBrazeClient(apiKey: "other-key")
        destination.start(client: otherClient)
        identify(destination, userId: "u2", ["plan": "max"])
        destination.reset()
        client.calls.removeAll()
        destination.start(client: client)
        identify(destination, userId: "u1", ["plan": "pro"])
        XCTAssertEqual(client.calls, [])
        otherClient.calls.removeAll()
        destination.start(client: otherClient)
        identify(destination, userId: "u2", ["plan": "max"])
        XCTAssertEqual(otherClient.calls, [.changeUser("u2"), .update(.customAttribute("plan", .string("max")))])
    }

    func testChangeUserAndResetClearTheCache() {
        let destination = makeDestination()
        identify(destination, userId: "u1", ["plan": "pro"])
        identify(destination, userId: "u2", ["plan": "pro"])
        destination.reset()
        identify(destination, userId: "u2", ["plan": "pro"])
        XCTAssertEqual(client.calls, [
            .changeUser("u1"), .update(.customAttribute("plan", .string("pro"))),
            .changeUser("u2"), .update(.customAttribute("plan", .string("pro"))),
            .changeUser("u2"), .update(.customAttribute("plan", .string("pro"))),
        ])
    }

    // MARK: - Track

    func testTrackPassesNamesThrough() {
        let destination = makeDestination()
        track(destination, "$Signed Up", ["$plan": "pro", "nested": ["items": [1, 2.5]], "none": NSNull()])
        track(destination, "No Properties")
        XCTAssertEqual(client.calls, [
            .customEvent("$Signed Up", ["$plan": "pro", "nested": ["items": [1, 2.5]]]),
            .customEvent("No Properties", nil),
        ])
    }

    func testOrderCompletedLogsOnePurchasePerProduct() {
        let destination = makeDestination()
        track(destination, "Order Completed", [
            "order_id": "o1",
            "revenue": 25.5,
            "currency": "EUR",
            "coupon": "ORDER",
            "products": [
                ["sku": "SKU1", "product_id": "p1", "name": "Shirt", "price": 10, "quantity": 2, "coupon": "C1", "$color": "red"],
                ["product_id": "p2", "name": "Hat", "price": "5.5", "quantity": 1],
                ["name": "Scarf", "price": 0, "quantity": 1],
                ["price": 1, "quantity": 1],
            ],
        ])
        XCTAssertEqual(client.calls, [
            .purchase("SKU1", "EUR", 10, 2, [
                "order_id": "o1", "revenue": 25.5, "currency": "EUR",
                "sku": "SKU1", "product_id": "p1", "name": "Shirt", "coupon": "C1", "$color": "red",
            ]),
            .purchase("p2", "EUR", 5.5, 1, ["order_id": "o1", "revenue": 25.5, "currency": "EUR", "coupon": "ORDER", "product_id": "p2", "name": "Hat"]),
            .purchase("Scarf", "EUR", 0, 1, ["order_id": "o1", "revenue": 25.5, "currency": "EUR", "coupon": "ORDER", "name": "Scarf"]),
        ])
    }

    func testPriceIsRequiredAndSuppliedQuantityIsValidatedInBothGroupingModes() throws {
        let invalid: [Any?] = [nil, NSNull(), true, "", " ", "12oops", "NaN", "Infinity", "1e309", "0x10"]
        for grouping: BrazeDestination.Options.PurchaseGrouping in [.perOrder, .perProduct(identifier: .sku)] {
            let destination = makeDestination(.init(purchaseGrouping: grouping))
            for quantity in [false, true] {
                for value in invalid + (quantity ? [0, -1, 1.5, 101] : []) {
                    if quantity, value == nil { continue }
                    var product: [String: Any] = ["sku": "SKU1", "price": 2, "quantity": 1]
                    product[quantity ? "quantity" : "price"] = value
                    var order: [String: Any] = ["currency": "USD", "products": [product], "revenue": 2, "quantity": 1]
                    order[quantity ? "quantity" : "revenue"] = value
                    if !quantity, value != nil { order["total"] = 99 }
                    XCTAssertThrowsError(try destination.forwardTrack(TrackEvent(event: "Order Completed", properties: try JSON(order)), to: client)) {
                        XCTAssertEqual($0 as? BrazeDestinationError, quantity ? .invalidQuantity : .invalidPrice)
                    }
                }
            }
        }
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testOmittedQuantityDefaultsToOneInBothGroupingModes() {
        for grouping: BrazeDestination.Options.PurchaseGrouping in [.perOrder, .perProduct(identifier: .sku)] {
            let destination = makeDestination(.init(purchaseGrouping: grouping, transformPurchase: { purchase, _ in
                XCTAssertEqual(purchase.quantity, 1)
                return purchase
            }))
            for products: [[String: Any]] in [[], [["sku": "SKU1", "price": 2]]] {
                client.calls.removeAll()
                track(destination, "Order Completed", ["currency": "USD", "revenue": 2, "products": products])
                guard case .purchase(_, _, let price, let quantity, _)? = client.calls.first else {
                    return XCTFail("Expected a purchase")
                }
                XCTAssertEqual(price, 2)
                XCTAssertEqual(quantity, 1)
                XCTAssertEqual(client.calls.count, 1)
            }
        }
    }

    func testExplicitZeroAndNumericStringsAreAccepted() throws {
        let destination = makeDestination()
        track(destination, "Order Completed", ["currency": "USD", "revenue": 0, "total": 99, "quantity": "2"])
        track(destination, "Order Completed", ["currency": "USD", "products": [["sku": "SKU1", "price": " 2.5e1 ", "quantity": "3"]]])
        XCTAssertEqual(client.calls, [
            .purchase("Order Completed", "USD", 0, 2, ["currency": "USD", "revenue": 0, "total": 99, "quantity": "2"]),
            .purchase("SKU1", "USD", 25, 3, ["currency": "USD", "sku": "SKU1"]),
        ])
    }

    func testTransformedPurchaseNumbersAreValidated() throws {
        for quantity in [false, true] {
            let destination = makeDestination(.init(transformPurchase: { purchase, _ in
                var purchase = purchase
                if quantity { purchase.quantity = 0 } else { purchase.price = .infinity }
                return purchase
            }))
            let event = TrackEvent(event: "Order Completed", properties: try JSON(["currency": "USD", "revenue": 2, "quantity": 1]))
            XCTAssertThrowsError(try destination.forwardTrack(event, to: client)) {
                XCTAssertEqual($0 as? BrazeDestinationError, quantity ? .invalidQuantity : .invalidPrice)
            }
        }
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testPurchaseCurrencyNormalization() {
        let destination = makeDestination()
        for (input, expected) in [(" eur\n", "EUR"), ("uSd", "USD"), ("btc", "BTC"), (" zzz ", "ZZZ")] {
            client.calls.removeAll()
            track(destination, "Order Completed", ["currency": input, "quantity": 1, "total": 12])
            XCTAssertEqual(client.calls, [.purchase("Order Completed", expected, 12, 1, ["currency": input, "quantity": 1, "total": 12])])
        }
    }

    func testInvalidPurchaseCurrencyThrowsWithoutDefault() throws {
        let destination = makeDestination()
        for value: Any? in [nil, NSNull(), 123, "", "   ", "dollars", "US", "123", "US1", "€€€", "éur", "US D"] {
            let properties = value.map { ["currency": $0] } ?? [:]
            let event = TrackEvent(event: "Order Completed", properties: try JSON(properties))
            XCTAssertThrowsError(try destination.forwardTrack(event, to: client)) {
                XCTAssertEqual($0 as? BrazeDestinationError, .invalidCurrency(value as? String))
            }
        }
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testExplicitDefaultCurrencyIsNormalizedAndOnlyUsedWhenNeeded() {
        let destination = makeDestination(.init(defaultCurrency: " gbp\n"))
        track(destination, "Order Completed", ["revenue": 0, "quantity": 1])
        track(destination, "Order Completed", ["currency": "US1", "revenue": 0, "quantity": 1])
        track(destination, "Order Completed", ["currency": "eur", "revenue": 0, "quantity": 1])
        XCTAssertEqual(client.calls, [
            .purchase("Order Completed", "GBP", 0, 1, ["revenue": 0, "quantity": 1]),
            .purchase("Order Completed", "GBP", 0, 1, ["currency": "US1", "revenue": 0, "quantity": 1]),
            .purchase("Order Completed", "EUR", 0, 1, ["currency": "eur", "revenue": 0, "quantity": 1]),
        ])
    }

    func testCurrencyRecognitionIsLeftToBrazeWithAnExplicitDefault() {
        let destination = makeDestination(.init(defaultCurrency: " zzz "))
        track(destination, "Order Completed", ["currency": "abc", "revenue": 2, "quantity": 1])
        track(destination, "Order Completed", ["revenue": 2, "quantity": 1])
        XCTAssertEqual(client.calls, [
            .purchase("Order Completed", "ABC", 2, 1, ["currency": "abc", "revenue": 2, "quantity": 1]),
            .purchase("Order Completed", "ZZZ", 2, 1, ["revenue": 2, "quantity": 1]),
        ])
    }

    func testInvalidDefaultCurrencyThrows() {
        let destination = makeDestination(.init(defaultCurrency: "US1"))
        XCTAssertThrowsError(try destination.forwardTrack(TrackEvent(event: "Order Completed", properties: nil), to: client)) {
            XCTAssertEqual($0 as? BrazeDestinationError, .invalidDefaultCurrency("US1"))
        }
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testTransformedCurrencyIsValidatedInBothGroupingModes() throws {
        for grouping: BrazeDestination.Options.PurchaseGrouping in [.perOrder, .perProduct(identifier: .sku)] {
            var currency = " zzz "
            let destination = makeDestination(.init(purchaseGrouping: grouping, transformPurchase: { purchase, _ in
                var purchase = purchase
                purchase.currency = currency
                return purchase
            }))
            let event = TrackEvent(event: "Order Completed", properties: try JSON(["currency": "USD", "revenue": 0, "quantity": 1, "products": [["sku": "SKU1", "price": 0, "quantity": 1]]]))
            client.calls.removeAll()
            try destination.forwardTrack(event, to: client)
            guard case .purchase(_, let sentCurrency, _, _, _)? = client.calls.first else {
                return XCTFail("Expected a purchase")
            }
            XCTAssertEqual(sentCurrency, "ZZZ")
            currency = "US1"
            XCTAssertThrowsError(try destination.forwardTrack(event, to: client)) {
                XCTAssertEqual($0 as? BrazeDestinationError, .invalidCurrency("US1"))
            }
            XCTAssertEqual(client.calls.count, 1)
        }
    }

    func testQueuedCurrencyErrorReachesErrorHandlerAndDoesNotStopReplay() {
        var errors = [BrazeDestinationError]()
        let analytics = Analytics(configuration: Configuration(writeKey: "braze-currency-\(UUID().uuidString)").errorHandler { error in
            if case AnalyticsError.pluginError(let error) = error, let error = error as? BrazeDestinationError {
                errors.append(error)
            }
        })
        let destination = makeDestination(start: false)
        destination.analytics = analytics
        track(destination, "Order Completed", ["currency": "US1", "revenue": 0, "quantity": 1])
        track(destination, "Next event")
        XCTAssertTrue(errors.isEmpty)
        destination.start(client: client)
        XCTAssertEqual(errors, [.invalidCurrency("US1")])
        XCTAssertEqual(client.calls, [.customEvent("Next event", nil)])
        withExtendedLifetime(analytics) {}
    }

    func testPurchaseProductIdentifierName() {
        let destination = makeDestination(.init(purchaseGrouping: .perProduct(identifier: .name), defaultCurrency: "USD"))
        track(destination, "Completed Order", ["products": [["sku": "SKU1", "name": "Shirt", "price": 10, "quantity": 1], ["sku": "SKU2", "price": 0, "quantity": 1]]])
        XCTAssertEqual(client.calls, [.purchase("Shirt", "USD", 10, 1, ["sku": "SKU1", "name": "Shirt"])])
    }

    func testOrderCompletedWithoutProducts() {
        let destination = makeDestination(.init(defaultCurrency: "USD"))
        track(destination, "Order Completed", ["quantity": 1, "total": 12, "currency": "dollars", "products": []])
        XCTAssertEqual(client.calls, [.purchase("Order Completed", "USD", 12, 1, ["quantity": 1, "total": 12, "currency": "dollars", "products": [Any]()])])
    }

    func testPerOrderPurchases() {
        let destination = makeDestination(.init(purchaseGrouping: .perOrder))
        let products: [[String: Any]] = [["sku": "SKU1", "name": "Shirt", "price": 10, "quantity": 2, "coupon": "C1"]]
        track(destination, "Order Completed", ["order_id": "o1", "revenue": 25, "quantity": 1, "currency": "EUR", "products": products])
        XCTAssertEqual(client.calls, [
            .purchase("Order Completed", "EUR", 25, 1, ["order_id": "o1", "revenue": 25, "quantity": 1, "currency": "EUR", "products": products]),
        ])
    }

    func testTransformPurchase() {
        var contexts = [PurchaseContext]()
        let destination = makeDestination(.init(defaultCurrency: "USD", transformPurchase: { purchase, context in
            contexts.append(context)
            guard context.product?["sku"] as? String != "SKIP" else { return nil }
            var purchase = purchase
            purchase.productId = "x-\(purchase.productId)"
            purchase.price *= 2
            purchase.currency = "EUR"
            purchase.quantity = 3
            purchase.properties = ["Transaction Id": context.order["order_id"] ?? ""]
            return purchase
        }))
        track(destination, "Order Completed", ["order_id": "o1", "products": [["sku": "SKU1", "price": 5, "quantity": 1], ["sku": "SKIP", "price": 0, "quantity": 1]]])
        track(destination, "Order Completed", ["order_id": "o2", "revenue": 4, "quantity": 1])
        XCTAssertEqual(client.calls, [
            .purchase("x-SKU1", "EUR", 10, 3, ["Transaction Id": "o1"]),
            .purchase("x-Order Completed", "EUR", 8, 3, ["Transaction Id": "o2"]),
        ])
        XCTAssertEqual(contexts.map { $0.event.event }, ["Order Completed", "Order Completed", "Order Completed"])
        XCTAssertEqual(contexts[0].product as NSDictionary?, ["sku": "SKU1", "price": 5, "quantity": 1])
        XCTAssertEqual(contexts[0].order["order_id"] as? String, "o1")
        XCTAssertNil(contexts[2].product)
    }

    func testTransformPurchaseInPerOrderMode() {
        var product: [String: Any]? = ["unset": true]
        let destination = makeDestination(.init(purchaseGrouping: .perOrder, defaultCurrency: "USD", transformPurchase: { purchase, context in
            product = context.product
            return purchase
        }))
        track(destination, "Order Completed", ["revenue": 0, "quantity": 1, "products": [["sku": "SKU1", "price": 0, "quantity": 1]]])
        XCTAssertNil(product)
        XCTAssertEqual(client.calls, [.purchase("Order Completed", "USD", 0, 1, ["revenue": 0, "quantity": 1, "products": [["sku": "SKU1", "price": 0, "quantity": 1]]])])
    }

    func testPurchaseContextContainsPlainValuesForCompatibilityTransforms() {
        for isPerProduct in [true, false] {
            let grouping: BrazeDestination.Options.PurchaseGrouping = isPerProduct ? .perProduct(identifier: .sku) : .perOrder
            client.calls.removeAll()
            let destination = makeDestination(.init(purchaseGrouping: grouping, defaultCurrency: "USD", transformPurchase: { purchase, context in
                let products = context.order["products"] as! [[String: Any]]
                let product = context.product ?? products[0]
                let details = product["details"] as! [String: Any]
                XCTAssertEqual(String(describing: context.order["channel"]!), "app")
                XCTAssertEqual(String(describing: product["name"]!), "Resistance Band")
                XCTAssertEqual(String(describing: details["color"]!), "blue")
                XCTAssertEqual(String(describing: product["price"]!), "15")
                XCTAssertEqual(String(describing: details["available"]!), "true")
                XCTAssertEqual(String(describing: (details["sizes"] as! [Any])[0]), "42")
                var purchase = purchase
                purchase.properties = [
                    "Name": String(describing: product["name"]!),
                    "channel": String(describing: context.order["channel"]!),
                    "color": String(describing: details["color"]!),
                ]
                return purchase
            }))
            track(destination, "Order Completed", [
                "channel": "app", "revenue": 30, "quantity": 1,
                "products": [["sku": "RB-100", "name": "Resistance Band", "price": 15, "quantity": 2,
                              "details": ["color": "blue", "available": true, "sizes": [42]]]],
            ])
            XCTAssertEqual(client.calls, [.purchase(isPerProduct ? "RB-100" : "Order Completed", "USD",
                                                   isPerProduct ? 15 : 30, isPerProduct ? 2 : 1,
                                                   ["Name": "Resistance Band", "channel": "app", "color": "blue"])])
        }
    }

    func testTransformPurchaseCanSetMissingProductId() {
        let destination = makeDestination(.init(defaultCurrency: "USD", transformPurchase: { purchase, context in
            var purchase = purchase
            if purchase.productId.isEmpty {
                purchase.productId = context.product?["id"] as? String ?? ""
            }
            return purchase
        }))
        track(destination, "Order Completed", ["products": [["id": "custom-1", "price": 3, "quantity": 1]]])
        XCTAssertEqual(client.calls, [.purchase("custom-1", "USD", 3, 1, ["id": "custom-1"])])
    }

    func testTransformPurchaseWithEmptyProductIdIsSkipped() {
        let destination = makeDestination(.init(defaultCurrency: "USD", transformPurchase: { purchase, _ in
            var purchase = purchase
            purchase.productId = ""
            return purchase
        }))
        track(destination, "Order Completed", ["products": [["sku": "SKU1", "price": 0, "quantity": 1]]])
        XCTAssertEqual(client.calls, [])
    }

    func testDefaultPurchaseEventNames() {
        let destination = makeDestination(.init(defaultCurrency: "USD"))
        track(destination, "Order Completed", ["revenue": 0, "quantity": 1])
        track(destination, "Completed Order", ["revenue": 0, "quantity": 1])
        track(destination, "order completed")
        XCTAssertEqual(client.calls, [
            .purchase("Order Completed", "USD", 0, 1, ["revenue": 0, "quantity": 1]),
            .purchase("Completed Order", "USD", 0, 1, ["revenue": 0, "quantity": 1]),
            .customEvent("order completed", nil),
        ])
    }

    func testCustomPurchaseEventNames() {
        let destination = makeDestination(.init(purchaseDetection: .eventNames(["Membership Purchased"]), defaultCurrency: "USD"))
        track(destination, "Membership Purchased", ["revenue": 20, "quantity": 1])
        track(destination, "Order Completed")
        XCTAssertEqual(client.calls, [
            .purchase("Membership Purchased", "USD", 20, 1, ["revenue": 20, "quantity": 1]),
            .customEvent("Order Completed", nil),
        ])
    }

    func testCustomPurchaseDetection() {
        let destination = makeDestination(.init(purchaseDetection: .matcher { $0.event == "Membership Purchased" }, defaultCurrency: "USD"))
        track(destination, "Membership Purchased", ["revenue": 0, "quantity": 1])
        track(destination, "Order Completed")
        XCTAssertEqual(client.calls, [
            .purchase("Membership Purchased", "USD", 0, 1, ["revenue": 0, "quantity": 1]),
            .customEvent("Order Completed", nil),
        ])
    }

    func testInstallAttributedSetsAttributionData() {
        let destination = makeDestination()
        track(destination, "Install Attributed", ["campaign": ["source": "Google", "name": "Fall", "ad_group": "G1"]])
        XCTAssertEqual(client.calls, [
            .attribution("Google", "Fall", "G1", ""),
            .customEvent("Install Attributed", ["campaign": ["source": "Google", "name": "Fall", "ad_group": "G1"]]),
        ])
    }

    // MARK: - Screen, opt-out, flush

    func testScreenViewsAreForwardedOnlyWhenEnabled() {
        let screen = ScreenEvent(title: "Home", category: nil, properties: try! JSON(["tab": "feed"]))
        _ = makeDestination().screen(event: screen)
        _ = makeDestination(.init(forwardScreenViews: true)).screen(event: screen)
        XCTAssertEqual(client.calls, [.customEvent("Home", ["tab": "feed"])])
    }

    func testPerEventOptOut() {
        let destination = makeDestination()
        track(destination, "A", integrations: ["Appboy": false])
        track(destination, "B", integrations: ["All": false])
        track(destination, "C", integrations: ["All": false, "Appboy": true])
        XCTAssertEqual(client.calls, [.customEvent("C", nil)])
    }

    func testFlushRequestsImmediateDataFlush() {
        makeDestination().flush()
        XCTAssertEqual(client.calls, [.flush])
    }

    // MARK: - Readiness

    func testPendingQueueDropsOldestOnOverflow() {
        let destination = makeDestination(start: false)
        for index in 0...BrazeDestination.maxPendingCount {
            track(destination, "Event \(index)")
        }
        XCTAssertTrue(client.calls.isEmpty)

        destination.start(client: client)

        XCTAssertEqual(client.calls, (1...BrazeDestination.maxPendingCount).map {
            .customEvent("Event \($0)", nil)
        })
        track(destination, "After startup")
        XCTAssertEqual(client.calls.last, .customEvent("After startup", nil))
    }

    func testPurchaseMatcherCanWaitForConcurrentTrack() {
        assertPurchaseCallbackCanWaitForConcurrentTrack(transform: false, replay: false)
    }

    func testPurchaseTransformerCanWaitForConcurrentTrack() {
        assertPurchaseCallbackCanWaitForConcurrentTrack(transform: true, replay: false)
    }

    func testQueuedPurchaseMatcherCanWaitForConcurrentTrack() {
        assertPurchaseCallbackCanWaitForConcurrentTrack(transform: false, replay: true)
    }

    func testQueuedPurchaseTransformerCanWaitForConcurrentTrack() {
        assertPurchaseCallbackCanWaitForConcurrentTrack(transform: true, replay: true)
    }

    private func assertPurchaseCallbackCanWaitForConcurrentTrack(transform: Bool, replay: Bool) {
        let entered = DispatchSemaphore(value: 0)
        let concurrentTrackReturned = DispatchSemaphore(value: 0)
        let drained = expectation(description: "Braze operations drained")
        let callback = {
            entered.signal()
            // Bound the wait so a regression fails instead of hanging the test process.
            XCTAssertEqual(concurrentTrackReturned.wait(timeout: .now() + 2), .success)
        }
        var options = BrazeDestination.Options(defaultCurrency: "USD")
        if transform {
            options.transformPurchase = { purchase, _ in
                callback()
                return purchase
            }
        } else {
            options.purchaseDetection = .matcher { event in
                guard event.event == "Order Completed" else { return false }
                callback()
                return true
            }
        }
        let destination = makeDestination(options, start: !replay)
        let client = self.client!
        if replay {
            track(destination, "Order Completed", ["revenue": 0, "quantity": 1])
            track(destination, "Already queued")
        }
        DispatchQueue.global().async {
            if replay {
                destination.start(client: client)
            } else {
                self.track(destination, "Order Completed", ["revenue": 0, "quantity": 1])
            }
            drained.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        identify(destination, userId: "u2")
        track(destination, "Concurrent")
        concurrentTrackReturned.signal()
        wait(for: [drained], timeout: 5)

        var expected: [FakeBrazeClient.Call] = [.purchase("Order Completed", "USD", 0, 1, ["revenue": 0, "quantity": 1])]
        if replay { expected.append(.customEvent("Already queued", nil)) }
        expected += [.changeUser("u2"), .customEvent("Concurrent", nil)]
        XCTAssertEqual(client.calls, expected)
    }

    func testReentrantOperationsFollowQueuedEvents() {
        var onTrack: (() -> Void)?
        let destination = makeDestination(.init(purchaseDetection: .matcher { event in
            if event.event == "Outer" { onTrack?() }
            return false
        }), start: false)
        onTrack = { [unowned destination] in
            self.track(destination, "Nested")
            destination.reset()
            self.identify(destination, userId: "u1", ["plan": "pro"])
            destination.flush()
        }
        identify(destination, userId: "u1", ["plan": "pro"])
        track(destination, "Outer")
        track(destination, "Already queued")
        destination.start(client: client)

        XCTAssertEqual(client.calls, [
            .changeUser("u1"), .update(.customAttribute("plan", .string("pro"))),
            .customEvent("Outer", nil), .customEvent("Already queued", nil),
            .customEvent("Nested", nil),
            .changeUser("u1"), .update(.customAttribute("plan", .string("pro"))),
            .flush,
        ])
    }

    func testConcurrentClientReplacementPreservesEventAndCacheOrdering() {
        let entered = DispatchSemaphore(value: 0)
        let attached = DispatchSemaphore(value: 0)
        let drained = expectation(description: "Client replacement drained")
        let destination = makeDestination(.init(purchaseDetection: .matcher { event in
            if event.event == "Outer" {
                entered.signal()
                XCTAssertEqual(attached.wait(timeout: .now() + 2), .success)
            }
            return false
        }), start: false)
        identify(destination, userId: "u1", ["plan": "pro"])
        track(destination, "Outer")
        track(destination, "Already queued")
        let originalClient = client!
        DispatchQueue.global().async {
            destination.start(client: originalClient)
            drained.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        let replacement = FakeBrazeClient(apiKey: "other-key")
        destination.start(client: replacement)
        identify(destination, userId: "u2", ["plan": "max"])
        track(destination, "After replacement")
        attached.signal()
        wait(for: [drained], timeout: 5)
        XCTAssertEqual(originalClient.calls, [
            .changeUser("u1"), .update(.customAttribute("plan", .string("pro"))),
            .customEvent("Outer", nil), .customEvent("Already queued", nil),
        ])
        XCTAssertEqual(replacement.calls, [
            .changeUser("u2"), .update(.customAttribute("plan", .string("max"))),
            .customEvent("After replacement", nil),
        ])
        client = FakeBrazeClient(userId: "u1")
        identify(makeDestination(), userId: "u1", ["plan": "pro"])
        XCTAssertEqual(client.calls, [], "Replacement must not overwrite the original client's cache")
    }

    func testEventsQueueUntilBrazeIsReady() {
        let destination = makeDestination(start: false)
        var readyCount = 0
        destination.onClientReady { _ in readyCount += 1 }
        identify(destination, userId: "u1")
        track(destination, "A")
        destination.flush()
        XCTAssertEqual(client.calls, [])
        XCTAssertEqual(readyCount, 0)

        destination.start(client: client)
        XCTAssertEqual(client.calls, [.changeUser("u1"), .customEvent("A", nil), .flush])
        XCTAssertEqual(readyCount, 1)
        destination.onClientReady { _ in readyCount += 1 }
        XCTAssertEqual(readyCount, 2)
    }

    func testReceivesEventsWithoutRemoteSettings() {
        let analytics = Analytics(configuration: Configuration(writeKey: "braze-destination-test"))
        analytics.add(plugin: makeDestination())
        let deadline = Date().addingTimeInterval(5)
        while analytics.find(pluginType: StartupQueue.self)?.running != true && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        analytics.track(name: "Opened")
        XCTAssertTrue(client.calls.contains(.customEvent("Opened", nil)))
    }
}

#if canImport(BrazeKit)
import BrazeKit

extension BrazeDestination_Tests {
    func testConfigInCodeInitializesBrazeImmediately() {
        let destination = BrazeDestination(apiKey: "test-api-key", endpoint: "sdk.iad-01.braze.com") { $0.logger.level = .error }
        var readyInstance: Braze?
        destination.onReady { readyInstance = $0 }
        XCTAssertNotNil(destination.braze)
        XCTAssertTrue(readyInstance === destination.braze)
        XCTAssertEqual(destination.currentClient?.stateStorageKey,
                       BrazeDestination.storageKey(apiKey: "test-api-key", endpoint: "sdk.iad-01.braze.com"))
    }
}
#endif
