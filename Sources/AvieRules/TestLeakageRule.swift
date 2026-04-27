import AvieCore
import AvieGraph

public struct TestLeakageRule: Rule {
    public let id = RuleID.testLeakage
    public let severity = Finding.Severity.error
    public let name = "Test Leakage"
    public let description = "Finds test-only dependencies that are reachable from production targets."

    public init() {}

    public func analyze(
        graph: DependencyGraph,
        traversal: GraphTraversal,
        context: RuleContext
    ) throws -> [Finding] {
        guard let targets = context.targets else { return [] }

        var testPackages = Set<PackageIdentity>()
        var prodPackages = Set<PackageIdentity>()

        for target in targets {
            let deps = target.packageDependencies
            if target.isProduction {
                prodPackages.formUnion(deps)
            } else {
                testPackages.formUnion(deps)
            }
        }

        let strictlyTestPackages = testPackages.subtracting(prodPackages)
        var findings: [Finding] = []

        var prodReachable = Set<PackageIdentity>()
        for prodTarget in targets where prodTarget.isProduction {
            for dep in prodTarget.packageDependencies {
                prodReachable.insert(dep)
                prodReachable.formUnion(traversal.reachablePackages(from: dep))
            }
        }

        for testPkg in strictlyTestPackages {
            if prodReachable.contains(testPkg) {
                findings.append(Finding(
                    ruleID: id,
                    severity: severity,
                    confidence: .proven,
                    summary: "Test dependency '\(testPkg)' leaked into production graph.",
                    detail: "This package is only directly depended on by a test target, but is transitively reachable from a production target.",
                    graphPath: [graph.rootIdentity, testPkg], // Simplified path for now
                    suggestedAction: "Check production dependencies. You may be importing a test library in production code.",
                    affectedPackage: testPkg
                ))
            }
        }

        return findings
    }
}
