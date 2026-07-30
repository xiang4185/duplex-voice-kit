// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DuplexVoiceKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DuplexVoiceKit",
            targets: ["DuplexVoiceKit"]
        )
    ],
    targets: [
        .target(
            name: "DuplexVoiceKit"
        ),
        .testTarget(
            name: "DuplexVoiceKitTests",
            dependencies: ["DuplexVoiceKit"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
