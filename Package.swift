// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpenDisplay",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MPBridge", path: "Sources/MPBridge"),
        .executableTarget(name: "OpenDisplay", dependencies: ["MPBridge"], path: "Sources/OpenDisplay")
    ]
)
