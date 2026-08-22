// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BetaFeedbackDemo",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "BetaFeedbackDemo",
            dependencies: [
                .product(name: "BetaFeedbackKit", package: "BetaKit")
            ]
        )
    ]
)
