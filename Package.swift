// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "JustTypeIt",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "JustTypeIt",
            path: "Sources/JustTypeIt",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
