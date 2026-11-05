// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BarDisplay",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CGVirtualDisplayPrivate", path: "Sources/CGVirtualDisplayPrivate",
                linkerSettings: [.linkedFramework("CoreGraphics")]),
        .executableTarget(name: "BarDisplay", dependencies: ["CGVirtualDisplayPrivate"],
                          path: "Sources/BarDisplay", exclude: ["Info.plist"])
    ]
)
