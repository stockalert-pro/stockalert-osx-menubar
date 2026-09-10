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
    targets: [
        .executableTarget(
            name: "StockAlertMenuBar",
            path: "Sources/StockAlertMenuBar",
            exclude: ["Resources"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
