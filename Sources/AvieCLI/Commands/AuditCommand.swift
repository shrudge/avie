import ArgumentParser

struct AuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Run a full dependency graph audit."
    )

    mutating func run() throws {
        print("avie audit: not yet implemented")
    }
}
