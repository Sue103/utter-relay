// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceQuickRelay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VoiceQuickRelay",
            path: "Sources/VoiceQuickRelay"
        )
    ]
)
