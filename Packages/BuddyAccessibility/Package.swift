// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuddyAccessibility",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BuddyAccessibility", targets: ["BuddyAccessibility"]),
        .executable(name: "axdump", targets: ["axdump"]),
    ],
    dependencies: [
        .package(path: "../BuddyUIModel"),
    ],
    targets: [
        .target(
            name: "BuddyAccessibility",
            dependencies: [
                .product(name: "BuddyUIModel", package: "BuddyUIModel"),
            ]
        ),
        .executableTarget(
            name: "axdump",
            dependencies: [
                "BuddyAccessibility",
                .product(name: "BuddyUIModel", package: "BuddyUIModel"),
            ]
        ),
        .testTarget(
            name: "BuddyAccessibilityTests",
            dependencies: [
                "BuddyAccessibility",
                .product(name: "BuddyUIModel", package: "BuddyUIModel"),
            ]
        ),
    ]
)
