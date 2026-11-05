// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Sora",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sora",
            path: "Sources/Sora"
        )
    ]
)
