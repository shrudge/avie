import ArgumentParser
import Foundation
import AvieCore

/// `avie suppress AVIE001:some-package --reason "..."`
///
/// Adds an entry to avie-suppress.json to silence a specific finding.
///
/// Bug 3 Fix: Reverted to the architecture-specified positional <key> argument
/// (§11.6) rather than split --rule/--package flags. The key format is
/// ruleID:packageIdentity (e.g. AVIE003:grdb).
///
/// Design rationale (§13.3): The compound key format is intentional.
/// Suppression keys are identity-based, not graph-state-based, so they survive
/// dependency graph reorganizations without causing Git merge conflicts.
struct SuppressCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "suppress",
        abstract: "Add a suppression for a specific finding.",
        discussion: """
            Key format: RULE_ID:package-identity
            Example: avie suppress AVIE003:grdb --reason "GRDB fanout is expected and reviewed."
            
            Keys are stored in avie-suppress.json and are stable across graph changes.
            They identify a specific (rule, package) pair, not a graph state.
            """
    )

    @Argument(help: "Suppression key in format RULE_ID:package-identity (e.g. AVIE003:grdb)")
    var key: String

    @Option(name: .shortAndLong, help: "Reason for suppression (mandatory, must be non-empty)")
    var reason: String

    @Option(name: .long, help: "Author name (defaults to $USER environment variable)")
    var who: String?

    mutating func validate() throws {
        if reason.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("--reason must not be empty")
        }
        if !key.contains(":") {
            throw ValidationError("""
                Invalid suppression key format: '\(key)'
                Expected format: RULE_ID:package-identity (e.g. AVIE003:grdb)
                """)
        }
    }

    mutating func run() throws {
        let packageURL = URL(fileURLWithPath: ".").standardized
        var file = (try? SuppressionFile.load(from: packageURL)) ?? SuppressionFile()

        let addedBy = who ?? ProcessInfo.processInfo.environment["USER"] ?? "unknown"
        let addedAt = ISO8601DateFormatter().string(from: Date())

        file.suppressions.append(Suppression(
            key: key,
            reason: reason,
            addedBy: addedBy,
            addedAt: addedAt
        ))

        try file.save(to: packageURL)

        print("Suppression added: \(key)")
        print("  Reason: \(reason)")
        print("  By: \(addedBy) at \(addedAt)")
        print("  Saved to \(SuppressionFile.fileName)")
    }
}
