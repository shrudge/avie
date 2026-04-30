import AvieCore
import AvieGraph

/// Warns when a direct dependency introduces too many transitive dependencies.
///
/// The threshold is applied to the **unique set of transitive packages** reachable
/// from the direct dependency, excluding the direct dependency itself.
///
/// For example, if Package A depends on Package B and Package C, and both B and C
/// depend on Package D:
/// - Direct dependencies: B, C
/// - Transitive dependencies of A (via B/C): D
/// - Total count for A: 1 (Package D)
///
/// This rule helps identify "heavy" dependencies that might bloat the graph
/// and increase resolution time.
public struct ExcessiveFanoutRule: Rule {
    public let id = RuleID.excessiveFanout
    public let severity = Finding.Severity.warning
    public let name = "Excessive Fanout"
    public let description = "Warns when a direct dependency introduces too many transitive dependencies."

    public init() {}

    public func analyze(
        graph: DependencyGraph,
        traversal: GraphTraversal,
        context: RuleContext
    ) throws -> [Finding] {
        let threshold = context.configuration.rules.fanoutThreshold
        let directDeps = graph.adjacency[graph.rootIdentity] ?? []
        var findings: [Finding] = []

        for dep in directDeps {
            let transitive = traversal.allTransitiveDependencies(of: dep)
            if transitive.count > threshold {
                let pkg = graph.packages[dep]!
                findings.append(Finding(
                    ruleID: id,
                    severity: severity,
                    confidence: .proven,
                    summary: "'\(pkg.name)' introduces \(transitive.count) transitive dependencies (threshold: \(threshold)).",
                    detail: "This single dependency pulls in \(transitive.count) other packages transitively. Consider whether the functionality justifies the dependency weight.",
                    graphPath: [graph.rootIdentity, dep],
                    suggestedAction: "Evaluate if '\(pkg.name)' can be replaced with a lighter alternative or if the threshold should be raised.",
                    affectedPackage: dep
                ))
            }
        }

        return findings
    }
}
