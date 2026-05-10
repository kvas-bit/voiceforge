// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "VoiceForge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoiceForge", targets: ["VoiceForge"])
    ],
    targets: [
        .executableTarget(
            name: "VoiceForge",
            exclude: ["Resources/AppIcon.icon"]
        ),
        .testTarget(
            name: "VoiceForgeTests",
            dependencies: ["VoiceForge"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
