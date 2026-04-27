import AvieCore
import AvieGraph

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
