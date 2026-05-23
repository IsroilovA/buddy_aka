// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuddySession",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BuddySession", targets: ["BuddySession"]),
    ],
    dependencies: [
        .package(path: "../BuddyAccessibility"),
    ],
    targets: [
        .target(
            name: "BuddySession",
            dependencies: [
                .product(name: "BuddyAccessibility", package: "BuddyAccessibility"),
            ]
        ),
        .testTarget(
            name: "BuddySessionTests",
            dependencies: ["BuddySession"]
        ),
    ]
)
