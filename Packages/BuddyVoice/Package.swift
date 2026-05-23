// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuddyVoice",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BuddyVoice", targets: ["BuddyVoice"]),
    ],
    targets: [
        .target(name: "BuddyVoice"),
        .testTarget(
            name: "BuddyVoiceTests",
            dependencies: ["BuddyVoice"]
        ),
    ]
)
