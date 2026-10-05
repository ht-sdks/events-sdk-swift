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

    func changeUser(userId: String) { calls.append(.changeUser(userId)) }
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
        client.calls.removeAll()
        identify(makeDestination(), userId: "u1", ["plan": "pro"])
        XCTAssertEqual(client.calls, [])
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
                ["product_id": "p2", "name": "Hat", "price": "5.5"],
                ["name": "Scarf"],
                ["price": 1],
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

    func testPurchaseProductIdentifierName() {
        let destination = makeDestination(.init(purchaseGrouping: .perProduct(identifier: .name)))
        track(destination, "Completed Order", ["products": [["sku": "SKU1", "name": "Shirt", "price": 10], ["sku": "SKU2"]]])
        XCTAssertEqual(client.calls, [.purchase("Shirt", "USD", 10, 1, ["sku": "SKU1", "name": "Shirt"])])
    }

    func testOrderCompletedWithoutProducts() {
        let destination = makeDestination()
        track(destination, "Order Completed", ["total": 12, "currency": "dollars", "products": []])
        XCTAssertEqual(client.calls, [.purchase("Order Completed", "USD", 12, 1, ["total": 12, "currency": "dollars", "products": [Any]()])])
    }

    func testPerOrderPurchases() {
        let destination = makeDestination(.init(purchaseGrouping: .perOrder))
        let products: [[String: Any]] = [["sku": "SKU1", "name": "Shirt", "price": 10, "quantity": 2, "coupon": "C1"]]
        track(destination, "Order Completed", ["order_id": "o1", "revenue": 25, "currency": "EUR", "products": products])
        XCTAssertEqual(client.calls, [
            .purchase("Order Completed", "EUR", 25, 1, ["order_id": "o1", "revenue": 25, "currency": "EUR", "products": products]),
        ])
    }

    func testTransformPurchase() {
        var contexts = [PurchaseContext]()
        let destination = makeDestination(.init(transformPurchase: { purchase, context in
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
        track(destination, "Order Completed", ["order_id": "o1", "products": [["sku": "SKU1", "price": 5], ["sku": "SKIP"]]])
        track(destination, "Order Completed", ["order_id": "o2", "revenue": 4])
        XCTAssertEqual(client.calls, [
            .purchase("x-SKU1", "EUR", 10, 3, ["Transaction Id": "o1"]),
            .purchase("x-Order Completed", "EUR", 8, 3, ["Transaction Id": "o2"]),
        ])
        XCTAssertEqual(contexts.map { $0.event.event }, ["Order Completed", "Order Completed", "Order Completed"])
        XCTAssertEqual(contexts[0].product as NSDictionary?, ["sku": "SKU1", "price": 5])
        XCTAssertEqual(contexts[0].order["order_id"] as? String, "o1")
        XCTAssertNil(contexts[2].product)
    }

    func testTransformPurchaseInPerOrderMode() {
        var product: [String: Any]? = ["unset": true]
        let destination = makeDestination(.init(purchaseGrouping: .perOrder, transformPurchase: { purchase, context in
            product = context.product
            return purchase
        }))
        track(destination, "Order Completed", ["products": [["sku": "SKU1"]]])
        XCTAssertNil(product)
        XCTAssertEqual(client.calls, [.purchase("Order Completed", "USD", 0, 1, ["products": [["sku": "SKU1"]]])])
    }

    func testTransformPurchaseCanSetMissingProductId() {
        let destination = makeDestination(.init(transformPurchase: { purchase, context in
            var purchase = purchase
            if purchase.productId.isEmpty {
                purchase.productId = context.product?["id"] as? String ?? ""
            }
            return purchase
        }))
        track(destination, "Order Completed", ["products": [["id": "custom-1", "price": 3]]])
        XCTAssertEqual(client.calls, [.purchase("custom-1", "USD", 3, 1, ["id": "custom-1"])])
    }

    func testTransformPurchaseWithEmptyProductIdIsSkipped() {
        let destination = makeDestination(.init(transformPurchase: { purchase, _ in
            var purchase = purchase
            purchase.productId = ""
            return purchase
        }))
        track(destination, "Order Completed", ["products": [["sku": "SKU1"]]])
        XCTAssertEqual(client.calls, [])
    }

    func testDefaultPurchaseEventNames() {
        let destination = makeDestination()
        track(destination, "Order Completed")
        track(destination, "Completed Order")
        track(destination, "order completed")
        XCTAssertEqual(client.calls, [
            .purchase("Order Completed", "USD", 0, 1, nil),
            .purchase("Completed Order", "USD", 0, 1, nil),
            .customEvent("order completed", nil),
        ])
    }

    func testCustomPurchaseEventNames() {
        let destination = makeDestination(.init(purchaseDetection: .eventNames(["Membership Purchased"])))
        track(destination, "Membership Purchased", ["revenue": 20])
        track(destination, "Order Completed")
        XCTAssertEqual(client.calls, [
            .purchase("Membership Purchased", "USD", 20, 1, ["revenue": 20]),
            .customEvent("Order Completed", nil),
        ])
    }

    func testCustomPurchaseDetection() {
        let destination = makeDestination(.init(purchaseDetection: .matcher { $0.event == "Membership Purchased" }))
        track(destination, "Membership Purchased")
        track(destination, "Order Completed")
        XCTAssertEqual(client.calls, [
            .purchase("Membership Purchased", "USD", 0, 1, nil),
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
    }
}
#endif
