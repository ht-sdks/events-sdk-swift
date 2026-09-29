// swift-tools-version:5.9

import PackageDescription

// Kept out of the root package so Hightouch consumers who don't use Braze never resolve braze-swift-sdk (and its SDWebImage dependency).
let package = Package(
    name: "HightouchBraze",
    platforms: [
        // BrazeKit has no macOS slice; macOS is declared so the mapping logic and tests build with `swift test` on the host.
        .macOS("10.15"),
        .iOS("13.0"),
        .tvOS("12.0"),
        .macCatalyst("13.0"),
    ],
    products: [
        .library(
            name: "HightouchBraze",
            targets: ["HightouchBraze"]),
    ],
    dependencies: [
        .package(name: "Hightouch", path: "../.."),
        .package(url: "https://github.com/braze-inc/braze-swift-sdk", "12.0.0"..<"19.0.0"),
    ],
    targets: [
        .target(
            name: "HightouchBraze",
            dependencies: [
                .product(name: "Hightouch", package: "Hightouch"),
                .product(name: "BrazeKit", package: "braze-swift-sdk", condition: .when(platforms: [.iOS, .tvOS, .macCatalyst, .visionOS])),
            ]),
        .testTarget(
            name: "HightouchBraze-Tests",
            dependencies: ["HightouchBraze"]),
    ]
)
