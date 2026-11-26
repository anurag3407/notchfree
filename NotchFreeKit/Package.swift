// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchFreeKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NotchFreeCore",
            targets: ["NotchFreeCore"]
        ),
        .library(
            name: "NotchFreeUI",
            targets: ["NotchFreeUI"]
        )
    ],
    targets: [
        .target(
            name: "NotchFreeCore",
            dependencies: [],
            path: "Sources/NotchFreeCore"
        ),
        .target(
            name: "NotchFreeUI",
            dependencies: ["NotchFreeCore"],
            path: "Sources/NotchFreeUI"
        ),
        .testTarget(
            name: "NotchFreeCoreTests",
            dependencies: ["NotchFreeCore"],
            path: "Tests/NotchFreeCoreTests"
        )
    ]
)
