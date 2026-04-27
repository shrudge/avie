import ArgumentParser
import AvieCore

struct ExplainCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explain",
        abstract: "Print a detailed explanation of a rule."
    )

    @Argument(help: "Rule ID to explain (e.g. AVIE001)")
    var ruleID: String

    mutating func run() throws {
        guard let rule = RuleID(rawValue: ruleID) else {
            print("Unknown rule ID: \(ruleID)")
            print("Available rules: \(RuleID.allCases.map(\.rawValue).joined(separator: ", "))")
            throw ExitCode.failure
        }

        switch rule {
        case .unreachablePin:
            printExplanation(
                id: "AVIE001",
                name: "Unreachable Pin",
                severity: "error",
                what: "Finds packages that exist in Package.resolved but are not reachable from the root package through any dependency chain.",
                why: """
                    Unreachable pins inflate resolution time, increase lockfile churn, and create \
                    false confidence that a dependency is actively used. They often appear after \
                    removing a dependency from Package.swift but forgetting to run `swift package update`.
                    """,
                fix: "Remove the package from your Package.swift dependencies array, then run `swift package resolve`.",
                example: "root → (no path to) → stale-package"
            )
        case .testLeakage:
            printExplanation(
                id: "AVIE002",
                name: "Test Leakage",
                severity: "error",
                what: "Finds test-only dependencies that are reachable from production targets.",
                why: """
                    Test-only packages (e.g. Quick, Nimble, SnapshotTesting) should never be \
                    linked into production binaries. If a test dependency leaks into the production \
                    graph, it increases binary size and may introduce security or licensing concerns.
                    """,
                fix: "Ensure test-only packages are only listed in .testTarget dependencies, not in .target dependencies.",
                example: "root → prod-target → test-framework (should only be in test targets)"
            )
        case .excessiveFanout:
            printExplanation(
                id: "AVIE003",
                name: "Excessive Fanout",
                severity: "warning",
                what: "Warns when a single direct dependency introduces more transitive dependencies than the configured threshold.",
                why: """
                    A dependency with high fanout dramatically increases your supply chain attack \
                    surface and build times. Each transitive dependency is a potential point of \
                    failure for version resolution conflicts.
                    """,
                fix: "Consider replacing the heavy dependency with a lighter alternative, or raise the threshold in .avie.json if the fanout is intentional.",
                example: "root → heavy-framework → (15+ transitive packages)"
            )
        case .binaryTargetIntroduced:
            printExplanation(
                id: "AVIE004",
                name: "Binary Target Introduced",
                severity: "warning",
                what: "Flags any package in the dependency graph that contains a binary target (.binaryTarget).",
                why: """
                    Binary targets are opaque — they cannot be audited for security vulnerabilities, \
                    license compliance, or unexpected behavior. They may also limit platform support \
                    and complicate debugging.
                    """,
                fix: "Verify the binary target is from a trusted source. If a source-based alternative exists, prefer it.",
                example: "root → package-with-xcframework"
            )
        }
    }

    private func printExplanation(
        id: String, name: String, severity: String,
        what: String, why: String, fix: String, example: String
    ) {
        print("Rule: \(id) — \(name)")
        print("Default Severity: \(severity)")
        print("")
        print("WHAT IT CHECKS:")
        print("  \(what)")
        print("")
        print("WHY IT MATTERS:")
        print("  \(why)")
        print("")
        print("HOW TO FIX:")
        print("  \(fix)")
        print("")
        print("EXAMPLE GRAPH PATH:")
        print("  \(example)")
    }
}
