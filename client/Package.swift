// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GlobalClick",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GlobalClick",
            path: "Sources/GlobalClick"
        )
    ]
)
