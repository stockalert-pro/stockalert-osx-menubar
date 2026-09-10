// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "StockAlertMenuBar",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "StockAlertMenuBar", targets: ["StockAlertMenuBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "StockAlertMenuBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/StockAlertMenuBar",
            exclude: ["Resources"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
