// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Foci",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "foci", targets: ["foci"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", exact: "0.6.0"),
    ],
    targets: [
        // Domain + application logic. Pure: no AppKit, no Accessibility, no file system.
        .target(name: "FociCore"),
        // macOS adapters: Accessibility, hotkeys, config/state files, menu bar.
        .target(name: "FociMac", dependencies: ["FociCore", "TOMLKit"]),
        // Composition root.
        .executableTarget(name: "foci", dependencies: ["FociCore", "FociMac"]),
        .testTarget(name: "FociCoreTests", dependencies: ["FociCore"]),
        .testTarget(name: "FociMacTests", dependencies: ["FociMac", "FociCore"]),
    ]
)
