// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DuplexVoiceKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DuplexVoiceKit", targets: ["DuplexVoiceKit"]),
        .library(name: "DuplexVoiceKitCompanion", targets: ["DuplexVoiceKitCompanion"]),
        .library(name: "DuplexVoiceKitUI", targets: ["DuplexVoiceKitUI"])
    ],
    targets: [
        .target(name: "DuplexVoiceKit"),
        .target(name: "DuplexVoiceKitCompanion"),
        .target(name: "DuplexVoiceKitUI", dependencies: ["DuplexVoiceKitCompanion", "DuplexVoiceKit"]),
        .testTarget(name: "DuplexVoiceKitTests", dependencies: ["DuplexVoiceKit"]),
        .testTarget(name: "DuplexVoiceKitCompanionTests", dependencies: ["DuplexVoiceKitCompanion"]),
        .testTarget(name: "DuplexVoiceKitUITests", dependencies: ["DuplexVoiceKitUI"])
    ],
    swiftLanguageVersions: [.v5]
)
