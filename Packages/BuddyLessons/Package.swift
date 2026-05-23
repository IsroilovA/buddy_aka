// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuddyLessons",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BuddyLessons", targets: ["BuddyLessons"]),
    ],
    dependencies: [
        .package(path: "../BuddyUIModel"),
        .package(path: "../BuddySession"),
    ],
    targets: [
        .target(
            name: "BuddyLessons",
            dependencies: [
                .product(name: "BuddyUIModel", package: "BuddyUIModel"),
                .product(name: "BuddySession", package: "BuddySession"),
            ]
        ),
        .testTarget(
            name: "BuddyLessonsTests",
            dependencies: [
                "BuddyLessons",
                .product(name: "BuddyUIModel", package: "BuddyUIModel"),
                .product(name: "BuddySession", package: "BuddySession"),
            ]
        ),
    ]
)
