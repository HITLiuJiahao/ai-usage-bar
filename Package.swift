// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AIUsageBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AIUsageBar", targets: ["AIUsageBar"])
    ],
    targets: [
        .executableTarget(
            name: "AIUsageBar",
            path: "Sources/AIUsageBar"
        )
    ]
)
