// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "Harbor",
            targets: ["Harbor"]
        ),
    ],
    dependencies: [
        // libmpv for iOS (same player engine Harbor uses on PC)
        .package(url: "https://github.com/mpvkit/MPVKit", exact: "1.1.0-n9.0.2"),
    ],
    targets: [
        .target(
            name: "Harbor",
            dependencies: [
                .product(name: "MPVKit", package: "MPVKit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
