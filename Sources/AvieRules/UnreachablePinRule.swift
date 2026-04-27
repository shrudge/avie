import AvieCore
import AvieGraph

public struct UnreachablePinRule: Rule {
    public let id = RuleID.unreachablePin
    public let severity = Finding.Severity.error
    public let name = "Unreachable Pin"
    public let description = "Finds packages in the resolved graph that are unreachable from the root."

    public init() {}

    public func analyze(
        graph: DependencyGraph,
        traversal: GraphTraversal,
        context: RuleContext
    ) throws -> [Finding] {
        guard let targets = context.targets else { return [] }

        var targetDeps = Set<PackageIdentity>()
        for target in targets {
            targetDeps.formUnion(target.packageDependencies)
        }

        var reachable = Set<PackageIdentity>()
        reachable.insert(graph.rootIdentity)
        for dep in targetDeps {
            reachable.insert(dep)
            reachable.formUnion(traversal.reachablePackages(from: dep))
        }

        var findings: [Finding] = []

        for packageID in graph.packages.keys where !reachable.contains(packageID) {
            let pkg = graph.packages[packageID]!
            findings.append(Finding(
                ruleID: id,
                severity: severity,
                confidence: .proven,
                summary: "Package '\(pkg.name)' is pinned but unreachable from the root.",
                detail: "This package exists in Package.resolved but no production or test target depends on it. It inflates resolution time and lockfile churn.",
                graphPath: [graph.rootIdentity],
                suggestedAction: "Remove '\(pkg.name)' from Package.swift dependencies.",
                affectedPackage: packageID
            ))
        }

        return findings
    }
}
