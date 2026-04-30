import ArgumentParser
import Foundation
import AvieCore

@main
struct Avie: ParsableCommand {
    private static var dynamicVersion: String {
        return Banner.render()
    }

    static let configuration = CommandConfiguration(
        commandName: "avie",
        abstract: "Swift package graph diagnostics tool.",
        version: dynamicVersion,
        subcommands: [
            AuditCommand.self,
            SuppressCommand.self,
            ExplainCommand.self,
            SnapshotCommand.self,
            DiffCommand.self,
        ],
        defaultSubcommand: AuditCommand.self
    )

    func validate() throws {
        // First run banner logic
        let home = FileManager.default.homeDirectoryForCurrentUser
        let marker = home.appendingPathComponent(".avie_first_run")
        
        if !FileManager.default.fileExists(atPath: marker.path) {
            print(Banner.render())
            // Create the marker file so we don't show it again
            try? "".write(to: marker, atomically: true, encoding: .utf8)
        }
    }
}
