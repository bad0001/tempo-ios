// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TempoCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TempoCore", targets: ["TempoCore"]),
    ],
    targets: [
        .target(name: "TempoCore"),
        .testTarget(name: "TempoCoreTests", dependencies: ["TempoCore"]),
    ]
)
