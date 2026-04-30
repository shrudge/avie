// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "unreachable-pin",
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "UnreachableLib",
            dependencies: []
        )
    ]
)