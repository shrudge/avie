import AvieCore
import AvieGraph

public struct BinaryTargetRule: Rule {
    public let id = RuleID.binaryTargetIntroduced
    public let severity = Finding.Severity.error
    public let name = "Binary Target Introduced"
    public let description = "Flags packages that contain binary targets."

    public init() {}

    public func analyze(
        graph: DependencyGraph,
        traversal: GraphTraversal,
        context: RuleContext
    ) throws -> [Finding] {
        var findings: [Finding] = []

        for (packageID, pkg) in graph.packages where pkg.containsBinaryTarget {
            let path = traversal.shortestPath(
                from: graph.rootIdentity, to: packageID
            ) ?? [graph.rootIdentity, packageID]

            findings.append(Finding(
                ruleID: id,
                severity: severity,
                confidence: .proven,
                summary: "Package '\(pkg.name)' contains a binary target.",
                detail: "Binary targets are opaque and cannot be audited for security or license compliance. They may also limit platform support.",
                graphPath: path,
                suggestedAction: "Verify that '\(pkg.name)' is from a trusted source and that the binary target is necessary.",
                affectedPackage: packageID
            ))
        }

        return findings
    }
}
