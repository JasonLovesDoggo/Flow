// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "FlowHelper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FlowHelper", targets: ["FlowHelper"]),
    ],
    targets: [
        .executableTarget(
            name: "FlowHelper",
            path: "Sources/FlowHelper"
        ),
    ]
)
