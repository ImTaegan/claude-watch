// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeWatchBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeWatchKit"),
        .executableTarget(name: "ClaudeWatchBar", dependencies: ["ClaudeWatchKit"]),
        .testTarget(name: "ClaudeWatchKitTests", dependencies: ["ClaudeWatchKit"]),
    ]
)
