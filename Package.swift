// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BarDisplay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BarDisplay", path: "Sources/BarDisplay", exclude: ["Info.plist"])
    ]
)
