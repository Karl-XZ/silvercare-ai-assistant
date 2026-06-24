// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "SilverCareiOS",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SilverCareCore",
            targets: ["SilverCareCore"]
        )
    ],
    targets: [
        .target(
            name: "SilverCareCore",
            path: "Sources/SilverCareCore",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .testTarget(
            name: "SilverCareCoreTests",
            dependencies: ["SilverCareCore"],
            path: "Tests/SilverCareCoreTests"
        )
    ]
)
