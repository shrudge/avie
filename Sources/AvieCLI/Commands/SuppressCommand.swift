import ArgumentParser
import Foundation
import AvieCore

struct SuppressCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "suppress",
        abstract: "Add a suppression for a specific finding."
    )

    @Option(name: .long, help: "Rule ID to suppress (e.g. AVIE001)")
    var rule: String

    @Option(name: .long, help: "Package identity to suppress (e.g. swift-argument-parser)")
    var package: String

    @Option(name: .shortAndLong, help: "Reason for suppression (mandatory)")
    var reason: String

    @Option(name: .long, help: "Author name (defaults to $USER)")
    var who: String?

    mutating func validate() throws {
        if reason.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("--reason must not be empty")
        }
    }

    mutating func run() throws {
        let key = "\(rule):\(`package`)"
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
        print("  By: \(addedBy)")
        print("  Saved to \(SuppressionFile.fileName)")
    }
}
