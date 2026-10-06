// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Hightouch",
    platforms: [
        .macOS("10.15"),
        .iOS("13.0"),
        .tvOS("12.0"),
        .macCatalyst("13.0"),
        .watchOS("7.1")
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Hightouch",
            targets: ["Hightouch"]),
        .library(
            name: "HightouchPush",
            targets: ["HightouchPush"]),
        .library(
            name: "HightouchBraze",
            targets: ["HightouchBraze"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/segmentio/Sovran-Swift.git", from: "1.1.0"),
        .package(url: "https://github.com/braze-inc/braze-swift-sdk", "12.0.0"..<"19.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Hightouch",
            dependencies: [
                .product(name: "Sovran", package: "sovran-swift")
            ],
            resources: [.process("Resources")]),
        .target(
            name: "HightouchPush",
            dependencies: ["Hightouch"],
            path: "Sources/HightouchPush"),
        .target(
            name: "HightouchBraze",
            dependencies: [
                "Hightouch",
                .product(name: "BrazeKit", package: "braze-swift-sdk", condition: .when(platforms: [.iOS, .tvOS, .macCatalyst, .visionOS])),
            ]),
        .testTarget(
            name: "Hightouch-Tests",
            dependencies: ["Hightouch"]),
        .testTarget(
            name: "HightouchPush-Tests",
            dependencies: ["HightouchPush", "Hightouch"],
            path: "Tests/HightouchPush-Tests"),
        .testTarget(
            name: "HightouchBraze-Tests",
            dependencies: ["HightouchBraze"]),
    ]
)
