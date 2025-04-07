// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SocialFusion",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "SocialFusion",
            targets: ["SocialFusion"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/realm/SwiftLint", from: "0.54.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "SocialFusion",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            plugins: [
                .plugin(name: "SwiftLintPlugin", package: "SwiftLint")
            ]
        ),
        .testTarget(
            name: "SocialFusionTests",
            dependencies: [
                "SocialFusion",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
