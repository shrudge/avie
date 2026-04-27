import ArgumentParser
import Foundation
import AvieCore

struct SuppressCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "suppress",
        abstract: "Suppress a specific finding by key."
    )

    @Argument(help: "Suppression key (e.g. AVIE001:some-package)")
    var key: String

    @Argument(help: "Reason for suppression")
    var reason: String

    @Option(name: .long, help: "Who is adding this suppression")
    var who: String?

    mutating func run() throws {
        let packageURL = URL(fileURLWithPath: ".").standardized
        var file = try SuppressionFile.load(from: packageURL)

        let addedBy = who ?? ProcessInfo.processInfo.environment["USER"] ?? "unknown"

        let formatter = ISO8601DateFormatter()
        let addedAt = formatter.string(from: Date())

        let suppression = Suppression(
            key: key,
            reason: reason,
            addedBy: addedBy,
            addedAt: addedAt
        )

        file.suppressions.append(suppression)
        try file.save(to: packageURL)

        print("Suppression added: \(key)")
        print("  Reason: \(reason)")
        print("  By: \(addedBy)")
        print("  Saved to \(SuppressionFile.fileName)")
    }
}
