import ArgumentParser
import Foundation
import AvieCore
import AvieResolver
import AvieGraph

struct ExplainCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explain",
        abstract: "Print a detailed explanation of why a package is in the graph."
    )

    @Argument(help: "The package identity to explain (e.g. swift-argument-parser)")
    var packageName: String

    @Option(name: .shortAndLong, help: "Path to package directory")
    var path: String = "."
    
    @Flag(name: .long, help: "CI mode: disable network resolution")
    var ci: Bool = false

    mutating func run() throws {
        let packageURL = URL(fileURLWithPath: path).standardized
        let resolver = SPMResolver(packageDirectory: packageURL, isCI: ci)
        try resolver.validate()

        let spmOutput = try resolver.resolve()
        let packages = DependencyTransformer().transform(spmOutput)
        let graph = try DependencyGraph(packages: packages)
        let traversal = GraphTraversal(graph: graph)

        let targetPackageID = PackageIdentity(packageName)
        guard let targetPkg = graph.packages[targetPackageID] else {
            print("Package '\(packageName)' not found in the dependency graph.")
            throw ExitCode.failure // Consider failure? Or 0. We'll use failure so scripts can detect.
        }

        let paths = traversal.allPaths(from: graph.rootIdentity, to: targetPackageID, maxPaths: 10)

        print("Package: \(targetPkg.name)")
        print("Version: \(targetPkg.version)")
        print("URL: \(targetPkg.url)")
        print("───────────────────────────")
        
        if paths.isEmpty {
            print("No path found from root to \(targetPkg.name).")
        } else {
            print("\(paths.count) path(s) to \(targetPkg.name) (showing up to 10):")
            for (index, path) in paths.enumerated() {
                let pathString = path.map { $0.value }.joined(separator: " → ")
                print("  \(index + 1). \(pathString)")
            }
        }
    }
}
