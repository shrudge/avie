import ArgumentParser
import Foundation
import AvieCore
import AvieResolver
import AvieGraph

struct AuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Run a full dependency graph audit."
    )

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

        let depth = traversal.maximumDepth(from: graph.rootIdentity)
        let directDeps = (graph.adjacency[graph.rootIdentity] ?? []).count

        print("Avie Dependency Graph Audit")
        print("───────────────────────────")
        print("Packages: \(graph.packages.count) total, \(directDeps) direct")
        print("Max depth: \(depth)")
        print("")
        print("✓ Graph resolved successfully. No rules executed (Phase 1).")
    }
}
