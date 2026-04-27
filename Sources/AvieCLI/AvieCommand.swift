import ArgumentParser

@main
struct Avie: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "avie",
        abstract: "Swift package graph diagnostics tool.",
        version: "1.0.0",
        subcommands: [AuditCommand.self],
        defaultSubcommand: AuditCommand.self
    )
}
