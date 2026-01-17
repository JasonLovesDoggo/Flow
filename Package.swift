// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #file).deletingLastPathComponent().path
let debugLibPath = "\(packageRoot)/flowwispr-core/target/debug/libflowwispr_core.a"
let releaseLibPath = "\(packageRoot)/flowwispr-core/target/release/libflowwispr_core.a"

let package = Package(
    name: "FlowWispr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FlowWispr",
            targets: ["FlowWispr"]
        ),
        .executable(
            name: "FlowWisprApp",
            targets: ["FlowWisprApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/amplitude/Amplitude-iOS", from: "8.0.0")
    ],
    targets: [
        // C wrapper for the Rust FFI
        .target(
            name: "CFlowWispr",
            path: "Sources/CFlowWispr",
            publicHeadersPath: "include",
            linkerSettings: [
                // Link to the Rust static library
                .unsafeFlags([debugLibPath], .when(configuration: .debug)),
                .unsafeFlags([releaseLibPath], .when(configuration: .release)),
                // System frameworks needed by the Rust library
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        // Swift wrapper
        .target(
            name: "FlowWispr",
            dependencies: ["CFlowWispr"],
            path: "Sources/FlowWispr"
        ),
        // macOS App
        .executableTarget(
            name: "FlowWisprApp",
            dependencies: [
                "FlowWispr",
                .product(name: "Amplitude", package: "Amplitude-iOS"),
            ],
            path: "Sources/FlowWisprApp",
            resources: [
                .process("Resources"),
                .copy("../../menubar.svg"),
            ]
        ),
    ]
)
