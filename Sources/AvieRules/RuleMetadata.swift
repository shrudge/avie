import AvieCore

/// Static lookup table that maps RuleID to human-readable rule metadata.
///
/// Bug 10 Fix: SARIFFormatter previously populated rule descriptions with
/// the raw rule ID string (e.g. "AVIE001"). The GitHub Security tab displays
/// these strings to developers; a raw ID is useless. This table provides
/// the human-readable name, description, and default SARIF level for each rule.
///
/// This is exported from AvieRules (not AvieCore) because rule metadata is
/// a concern of the rule system, not the core domain model.
public struct RuleMetadata {
    public let name: String
    public let shortDescription: String
    public let fullDescription: String
    /// SARIF level string: "error", "warning", or "note"
    public let sarifLevel: String

    public static func info(for ruleID: RuleID) -> RuleMetadata {
        switch ruleID {
        case .unreachablePin:
            return RuleMetadata(
                name: "Unreachable Pinned Package",
                shortDescription: "A package is pinned but not reachable from any root target.",
                fullDescription: """
                    A package is present in Package.resolved but no dependency path exists \
                    from the root package to this entry. This typically indicates a stale \
                    lockfile entry from a removed Package.swift dependency. \
                    Run `swift package resolve` to clean up the lockfile.
                    """,
                sarifLevel: "error"
            )
        case .testLeakage:
            return RuleMetadata(
                name: "Test Dependency Leaking Into Production Target",
                shortDescription: "A test-only dependency is transitively reachable from a production target.",
                fullDescription: """
                    A package declared as a dependency of a test target is also transitively \
                    reachable from a production target's dependency graph. Test frameworks \
                    (Quick, Nimble, etc.) must never be compiled into production binary artifacts \
                    as they risk inclusion in App Store builds.
                    """,
                sarifLevel: "error"
            )
        case .excessiveFanout:
            return RuleMetadata(
                name: "Excessive Transitive Fan-out",
                shortDescription: "A direct dependency introduces more transitive packages than the configured threshold.",
                fullDescription: """
                    A single direct dependency pulls in more transitive packages than the \
                    configured fanoutThreshold (default: 10). Review whether the dependency \
                    is appropriate for the scope of its use, or raise the threshold in .avie.json \
                    if this level of transitive depth is acceptable.
                    """,
                sarifLevel: "warning"
            )
        case .binaryTargetIntroduced:
            return RuleMetadata(
                name: "Binary Target Dependency",
                shortDescription: "A dependency contains a binary target (XCFramework) that cannot be source-audited.",
                fullDescription: """
                    A dependency contains a .binaryTarget declaration, meaning it distributes \
                    a pre-compiled XCFramework. Binary targets cannot be audited for security \
                    vulnerabilities, their code size contribution cannot be estimated without \
                    full compilation, and their licenses cannot be reviewed from source. \
                    This is a security and compliance gate that requires explicit review.
                    """,
                sarifLevel: "error"
            )
        }
    }
}
