//
//  ViewController.swift
//  BrazeExample
//

import UIKit
import Hightouch

class ViewController: UIViewController {
    private let lastActionLabel = UILabel()

    private var analytics: Analytics? {
        UIApplication.shared.delegate?.analytics
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        lastActionLabel.font = .preferredFont(forTextStyle: .body)
        lastActionLabel.numberOfLines = 0
        lastActionLabel.text = " "
        stack.addArrangedSubview(lastActionLabel)

        let actions: [(String, Selector)] = [
            ("Identify A", #selector(identifyA)),
            ("Identify A again", #selector(identifyAAgain)),
            ("Change plan", #selector(changePlan)),
            ("Custom event", #selector(customEvent)),
            ("Purchase, two products", #selector(purchaseTwoProducts)),
            ("Purchase, custom name", #selector(purchaseCustomName)),
            ("Screen", #selector(screen)),
            ("Opt-out event", #selector(optOutEvent)),
            ("Reset", #selector(reset)),
            ("Identify B", #selector(identifyB)),
        ]
        for (title, selector) in actions {
            stack.addArrangedSubview(makeButton(title, selector))
        }

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -32),
        ])
    }

    private func makeButton(_ title: String, _ selector: Selector) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: selector, for: .touchUpInside)
        return button
    }

    private func show(_ title: String) {
        lastActionLabel.text = title
    }

    private func userATraits(plan: String) -> [String: Any] {
        [
            "email": "jane@example.com",
            "firstName": "Jane",
            "gender": "male",
            "plan": plan,
            "address": [
                "city": "New York",
                "country": "US",
            ],
        ]
    }

    @objc private func identifyA() {
        analytics?.identify(userId: "user-a", traits: userATraits(plan: "pro"))
        show("Identify A")
    }

    @objc private func identifyAAgain() {
        analytics?.identify(userId: "user-a", traits: userATraits(plan: "pro"))
        show("Identify A again")
    }

    @objc private func changePlan() {
        analytics?.identify(userId: "user-a", traits: userATraits(plan: "enterprise"))
        show("Change plan")
    }

    @objc private func customEvent() {
        analytics?.track(name: "Class Booked", properties: ["class_type": "Yoga"])
        show("Custom event")
    }

    @objc private func purchaseTwoProducts() {
        analytics?.track(name: "Order Completed", properties: [
            "order_id": "order-123",
            "revenue": 42,
            "tax": 3,
            "currency": "USD",
            "products": [
                [
                    "sku": "RB-100",
                    "name": "Resistance Band",
                    "price": 15,
                    "quantity": 2,
                    "brand": "Equinox",
                    "category": "Gear",
                ],
                [
                    "sku": "MB-200",
                    "name": "Mat",
                    "price": 12,
                    "quantity": 1,
                    "brand": "Equinox",
                    "category": "Gear",
                ],
            ],
        ])
        show("Purchase, two products")
    }

    @objc private func purchaseCustomName() {
        analytics?.track(name: "Membership Purchased", properties: [
            "order_id": "order-456",
            "revenue": 99,
            "currency": "USD",
            "products": [
                [
                    "sku": "MEM-1",
                    "name": "Monthly Membership",
                    "price": 99,
                    "quantity": 1,
                ],
            ],
        ])
        show("Purchase, custom name")
    }

    @objc private func screen() {
        analytics?.screen(title: "Schedule")
        show("Screen")
    }

    @objc private func optOutEvent() {
        analytics?.track(name: "Private Event", enrichments: [{ event in
            guard var event = event else { return nil }
            event.integrations = try? JSON(["Appboy": false] as [String: Any])
            return event
        }])
        show("Opt-out event")
    }

    @objc private func reset() {
        analytics?.reset()
        show("Reset")
    }

    @objc private func identifyB() {
        analytics?.identify(userId: "user-b", traits: [
            "email": "bob@example.com",
            "firstName": "Bob",
        ])
        show("Identify B")
    }
}
