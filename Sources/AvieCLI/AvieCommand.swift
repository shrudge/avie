import ArgumentParser
import Foundation
import AvieCore

@main
struct Avie: ParsableCommand {
    private static var dynamicVersion: String {
        let repoRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptPath = repoRoot.appendingPathComponent("g.sh").path
        
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return "Avie Version: \(avieToolVersion)"
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        var env = ProcessInfo.processInfo.environment
        env["COLUMNS"] = "120"
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                let processedOutput = output.replacingOccurrences(of: "placeholder", with: avieToolVersion)
                return "\n" + processedOutput.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
            }
        } catch {
            return "Avie Version: \(avieToolVersion)"
        }
        
        return "Avie Version: \(avieToolVersion)"
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
}
