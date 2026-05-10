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
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "VoiceForgeTests",
            dependencies: ["VoiceForge"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
