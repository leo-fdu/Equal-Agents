// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "EqualAgents", platforms: [.macOS(.v14)], targets: [
    .executableTarget(name: "EqualAgents", path: "Sources/EqualAgents"),
    .testTarget(name: "EqualAgentsTests", dependencies: ["EqualAgents"], path: "tests/EqualAgentsTests")
])
