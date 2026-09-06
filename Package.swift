// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FloatDude",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "FloatDude",
            targets: ["FloatDude"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "FloatDude",
            path: "Sources/FloatDude"
        ),
        .testTarget(
            name: "FloatDudeTests",
            dependencies: ["FloatDude"],
            path: "Tests/FloatDudeTests"
        ),
    ]
)
