// swift-tools-version: 6.0
import PackageDescription

// Test fixture for Tests/E2E, not part of the main package. build.sh bundles it as Probe A, B and C.
let package = Package(
    name: "Probe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Probe", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
