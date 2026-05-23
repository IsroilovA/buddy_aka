// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuddyUIModel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BuddyUIModel", targets: ["BuddyUIModel"]),
    ],
    targets: [
        .target(name: "BuddyUIModel"),
        .testTarget(
            name: "BuddyUIModelTests",
            dependencies: ["BuddyUIModel"]
        ),
    ]
)
