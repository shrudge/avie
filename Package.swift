// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "avie",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "avie", targets: ["AvieCLI"]),
        .plugin(name: "AviePlugin", targets: ["AviePlugin"]),
        .library(name: "AvieCore", targets: ["AvieCore"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
    ],
    targets: [
        .target(name: "AvieCore", dependencies: []),
        .target(name: "AvieResolver", dependencies: ["AvieCore"]),
        .target(name: "AvieGraph", dependencies: ["AvieCore"]),
        .target(name: "AvieRules", dependencies: ["AvieCore", "AvieGraph"]),
        .target(name: "AvieDiff", dependencies: ["AvieCore", "AvieGraph", "AvieRules"]),
        .target(name: "AvieOutput", dependencies: ["AvieCore", "AvieRules", "AvieDiff"]),
        .executableTarget(
            name: "AvieCLI",
            dependencies: [
                "AvieCore", "AvieResolver", "AvieGraph",
                "AvieRules", "AvieDiff", "AvieOutput",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .plugin(
            name: "AviePlugin",
            capability: .command(
                intent: .custom(verb: "avie-audit", description: "Run Avie dependency graph audit"),
                permissions: [.writeToPackageDirectory(reason: "Write SARIF report")]
            )
        ),
        .testTarget(name: "AvieCoreTests", dependencies: ["AvieCore"]),
        .testTarget(name: "AvieResolverTests", dependencies: ["AvieResolver"]),
        .testTarget(name: "AvieGraphTests", dependencies: ["AvieGraph"]),
        .testTarget(name: "AvieRulesTests", dependencies: ["AvieRules", "AvieGraph"]),
        .testTarget(name: "AvieDiffTests", dependencies: ["AvieDiff"]),
        .testTarget(name: "AvieOutputTests", dependencies: ["AvieOutput"]),
    ]
)
