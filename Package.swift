// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TouchBarStudio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TouchBarStudio", targets: ["TouchBarStudio"]),
        .library(name: "TouchBarStudioCore", targets: ["TouchBarStudioCore"]),
    ],
    targets: [
        // UI-independent models, action system, storage, presets.
        .target(name: "TouchBarStudioCore"),
        // AppKit Touch Bar integration + SwiftUI interface.
        .executableTarget(
            name: "TouchBarStudio",
            dependencies: ["TouchBarStudioCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "TouchBarStudioCoreTests", dependencies: ["TouchBarStudioCore"]),
    ]
)
