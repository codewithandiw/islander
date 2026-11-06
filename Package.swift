// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Islander",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Islander",
            path: "Sources/Islander",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
