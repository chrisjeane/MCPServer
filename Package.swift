// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MCPServer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MCPServer", targets: ["MCPServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0")
    ],
    targets: [
        .target(
            name: "MCPServer"
        ),
        .testTarget(
            name: "MCPServerTests",
            dependencies: ["MCPServer", .product(name: "Testing", package: "swift-testing")]
        ),
    ]
)
