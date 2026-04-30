import ArgumentParser
import Foundation
import AvieCore

@main
struct Avie: ParsableCommand {
    private static func getBanner() -> String? {
        let repoRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptPath = repoRoot.appendingPathComponent("Banner.sh").path
        
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return nil
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
                return "\n" + processedOutput.trimmingCharacters(in: .newlines) + "\n\n"
            }
        } catch {
            return nil
        }
        return nil
    }

    private static var dynamicVersion: String {
        return getBanner() ?? "Avie Version: \(avieToolVersion)"
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
            if let banner = Self.getBanner() {
                print(banner)
                // Create the marker file so we don't show it again
                try? "".write(to: marker, atomically: true, encoding: .utf8)
            }
        }
    }
}
