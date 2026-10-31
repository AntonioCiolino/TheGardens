// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExperienceCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ExperienceCore", targets: ["ExperienceCore"]),
    ],
    targets: [
        .target(
            name: "ExperienceCore",
            path: "Sources/ExperienceCore"
        ),
        .testTarget(
            name: "ExperienceCoreTests",
            dependencies: ["ExperienceCore"],
            path: "Tests/ExperienceCoreTests"
        ),
    ]
)
