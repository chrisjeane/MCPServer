// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MCPServer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MCPServer", targets: ["MCPServer"]),
        .executable(name: "dice-server", targets: ["DiceServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0")
    ],
    targets: [
        .target(
            name: "MCPServer"
        ),
        .executableTarget(
            name: "DiceServer",
            dependencies: ["MCPServer"],
            path: "Examples/DiceServer"
        ),
        .testTarget(
            name: "MCPServerTests",
            dependencies: ["MCPServer", .product(name: "Testing", package: "swift-testing")]
        ),
    ]
)
