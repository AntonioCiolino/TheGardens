// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GardensCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GardensCore", targets: ["GardensCore"]),
    ],
    targets: [
        .target(
            name: "GardensCore",
            path: "Sources/GardensCore"
        ),
        .testTarget(
            name: "GardensCoreTests",
            dependencies: ["GardensCore"],
            path: "Tests/GardensCoreTests"
        ),
    ]
)
