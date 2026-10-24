// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DuoTrackpadCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DuoCore", targets: ["DuoCore"])],
    targets: [
        .target(name: "DuoCore", path: "Shared"),
        .testTarget(name: "DuoCoreTests", dependencies: ["DuoCore"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
