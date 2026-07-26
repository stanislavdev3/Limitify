// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Limitify",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LimitifyCore", targets: ["LimitifyCore"]),
        .executable(name: "Limitify", targets: ["LimitifyApp"]),
    ],
    targets: [
        .target(name: "LimitifyCore"),
        .executableTarget(
            name: "LimitifyApp",
            dependencies: ["LimitifyCore"]
        ),
        .testTarget(
            name: "LimitifyCoreTests",
            dependencies: ["LimitifyCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "LimitifyAppTests",
            dependencies: ["LimitifyApp"]
        ),
    ]
)
