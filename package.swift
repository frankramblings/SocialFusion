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
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.6.0"),
        .package(url: "https://github.com/SwiftUIX/SwiftUIX.git", from: "0.2.4"),
    ],
    targets: [
        .executableTarget(
            name: "SocialFusion",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftUIX", package: "SwiftUIX"),
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
