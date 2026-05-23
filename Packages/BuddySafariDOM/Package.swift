// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuddySafariDOM",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BuddySafariDOM", targets: ["BuddySafariDOM"]),
    ],
    dependencies: [
        .package(path: "../BuddyUIModel"),
    ],
    targets: [
        .target(
            name: "BuddySafariDOM",
            dependencies: [
                .product(name: "BuddyUIModel", package: "BuddyUIModel"),
            ]
        ),
        .testTarget(
            name: "BuddySafariDOMTests",
            dependencies: [
                "BuddySafariDOM",
                .product(name: "BuddyUIModel", package: "BuddyUIModel"),
            ]
        ),
    ]
)
