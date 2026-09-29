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

    func testReservedTraitsAndMParticleAliases() {
        let destination = makeDestination()
        identify(destination, [
            "first_name": "Jane",
            "$LastName": "Doe",
            "Email": "jane@example.com",
            "$Mobile": "555-0100",
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
            .update(.customAttribute("Zip", .string("78701"))),
            .update(.emailSubscription(.optedIn)),
            .update(.pushSubscription(.unsubscribed)),
        ])
    }

    func testTopLevelLocationAliases() {
        let destination = makeDestination()
        identify(destination, ["home_city": "Austin", "$Country": "US", "$Zip": "78701"])
        XCTAssertEqual(client.calls, [
            .update(.homeCity("Austin")),
            .update(.country("US")),
            .update(.customAttribute("Zip", .string("78701"))),
        ])
    }

    func testAgeEstimatesDateOfBirth() {
        let destination = makeDestination()
        identify(destination, ["$Age": 30])
        let year = Calendar.current.component(.year, from: Date()) - 30
        XCTAssertEqual(client.calls, [.update(.dateOfBirth(date(year, 1, 1)))])
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
            .update(.customAttribute("plan", .string("pro"))),
            .update(.customAttribute("active", .bool(true))),
            .update(.customAttribute("count", .int(3))),
            .update(.customAttribute("prefs", .string(#"{"a":"x","b":1}"#))),
            .update(.customAttribute("ratio", .double(1.5))),
            .update(.customAttribute("removed", nil)),
            .update(.customAttribute("tags", .stringArray(["a", "1", "true"]))),
        ])
    }

    func testStringifyAttributeValues() {
        let destination = makeDestination(.init(stringifyAttributeValues: true))
        identify(destination, ["count": 3, "active": true])
        track(destination, "Viewed", ["count": 3, "nested": ["a": 1]])
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

    func testTrackLogsCustomEventWithDollarsStripped() {
        let destination = makeDestination()
        track(destination, "$Signed Up", ["$plan": "pro", "nested": ["items": [1, 2.5]], "none": NSNull()])
        track(destination, "No Properties")
        XCTAssertEqual(client.calls, [
            .customEvent("Signed Up", ["plan": "pro", "nested": ["items": [1, 2.5]]]),
            .customEvent("No Properties", nil),
        ])
    }

    func testOrderCompletedLogsOnePurchasePerProduct() {
        let destination = makeDestination()
        track(destination, "Order Completed", [
            "order_id": "o1",
            "revenue": 25.5,
            "currency": "EUR",
            "products": [
                ["sku": "SKU1", "product_id": "p1", "name": "Shirt", "price": 10, "quantity": 2,
                 "brand": "B", "category": "Tops", "variant": "Red", "position": 1, "coupon": "C1", "$color": "red"],
                ["product_id": "p2", "name": "Hat", "price": "5.5"],
            ],
        ])
        XCTAssertEqual(client.calls, [
            .purchase("SKU1", "EUR", 10, 2, [
                "order_id": "o1", "revenue": 25.5, "Transaction Id": "o1",
                "product_id": "p1", "Name": "Shirt", "Brand": "B", "Category": "Tops", "Variant": "Red",
                "Position": 1, "Coupon Code": "C1", "color": "red",
            ]),
            .purchase("p2", "EUR", 5.5, 1, ["order_id": "o1", "revenue": 25.5, "Transaction Id": "o1", "Name": "Hat"]),
        ])
    }

    func testPurchaseProductIdentifierName() {
        let destination = makeDestination(.init(purchaseProductIdentifier: .name))
        track(destination, "Completed Order", ["products": [["sku": "SKU1", "name": "Shirt", "price": 10], ["sku": "SKU2"]]])
        XCTAssertEqual(client.calls, [.purchase("Shirt", "USD", 10, 1, ["Name": "Shirt"])])
    }

    func testOrderCompletedWithoutProducts() {
        let destination = makeDestination()
        track(destination, "Order Completed", ["total": 12, "currency": "dollars"])
        XCTAssertEqual(client.calls, [.purchase("Order Completed", "USD", 12, 1, ["total": 12])])
    }

    func testBundleCommerceEvents() {
        let destination = makeDestination(.init(bundleCommerceEvents: true))
        track(destination, "Order Completed", [
            "order_id": "o1",
            "revenue": 25,
            "products": [["sku": "SKU1", "name": "Shirt", "price": 10, "quantity": 2, "coupon": "C1"]],
        ])
        XCTAssertEqual(client.calls, [
            .purchase("eCommerce - purchase", "USD", 25, 1, [
                "order_id": "o1", "revenue": 25, "Transaction Id": "o1",
                "products": [["Id": "SKU1", "Name": "Shirt", "Price": 10, "Quantity": 2, "Coupon Code": "C1", "Total Product Amount": 20]],
            ]),
        ])
    }

    func testLogPurchaseWhenRevenuePresent() {
        track(makeDestination(), "Upgraded", ["revenue": 9.99])
        track(makeDestination(.init(logPurchaseWhenRevenuePresent: true)), "Upgraded", ["revenue": 9.99])
        track(makeDestination(.init(logPurchaseWhenRevenuePresent: true)), "Upgraded", ["revenue": 0])
        XCTAssertEqual(client.calls, [
            .customEvent("Upgraded", ["revenue": 9.99]),
            .purchase("Upgraded", "USD", 9.99, 1, ["revenue": 9.99]),
            .customEvent("Upgraded", ["revenue": 0]),
        ])
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
        let destination = makeDestination(.init(purchaseEventNames: ["Membership Purchased"]))
        track(destination, "Membership Purchased", ["revenue": 20])
        track(destination, "Order Completed")
        XCTAssertEqual(client.calls, [
            .purchase("Membership Purchased", "USD", 20, 1, ["revenue": 20]),
            .customEvent("Order Completed", nil),
        ])
    }

    func testIsPurchaseEventOverridesNamesAndRevenue() {
        let destination = makeDestination(.init(isPurchaseEvent: { $0.event == "Membership Purchased" }, logPurchaseWhenRevenuePresent: true))
        track(destination, "Membership Purchased")
        track(destination, "Order Completed")
        track(destination, "Upgraded", ["revenue": 9.99])
        XCTAssertEqual(client.calls, [
            .purchase("Membership Purchased", "USD", 0, 1, nil),
            .customEvent("Order Completed", nil),
            .customEvent("Upgraded", ["revenue": 9.99]),
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
