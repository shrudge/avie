import ArgumentParser
import Foundation
import AvieCore
import AvieDiff
import AvieOutput

struct DiffCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Compare two dependency graph snapshots (for PR analysis)."
    )

    @Option(name: .long, help: "Base branch snapshot JSON")
    var base: String

    @Option(name: .long, help: "Head (PR) branch snapshot JSON")
    var head: String

    @Option(name: .long, help: "Output format: terminal, json, sarif")
    var format: String = "terminal"

    @Flag(name: .long, help: "Disable color output")
    var noColor: Bool = false

    mutating func run() throws {
        let baseURL = URL(fileURLWithPath: base)
        let headURL = URL(fileURLWithPath: head)

        guard let baseData = try? Data(contentsOf: baseURL) else {
            print("Error: Could not read base snapshot at \(base)")
            throw ExitCode.failure
        }

        guard let headData = try? Data(contentsOf: headURL) else {
            print("Error: Could not read head snapshot at \(head)")
            throw ExitCode.failure
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let baseSnapshot: GraphSnapshot
        do {
            baseSnapshot = try decoder.decode(GraphSnapshot.self, from: baseData)
        } catch {
            print("Error: Base snapshot is malformed JSON")
            throw ExitCode.failure
        }

        let headSnapshot: GraphSnapshot
        do {
            headSnapshot = try decoder.decode(GraphSnapshot.self, from: headData)
        } catch {
            print("Error: Head snapshot is malformed JSON")
            throw ExitCode.failure
        }

        let engine = DiffEngine()
        let diffResult = engine.diff(base: baseSnapshot, head: headSnapshot)

        let formatter: OutputFormatter
        switch format.lowercased() {
        case "json":
            formatter = JSONFormatter()
        case "sarif":
            formatter = SARIFFormatter()
        case "terminal":
            formatter = TerminalFormatter(useColor: !noColor)
        default:
            print("Unknown format: \(format). Falling back to terminal.")
            formatter = TerminalFormatter(useColor: !noColor)
        }

        let output = try formatter.format(diff: diffResult)
        print(output)

        if diffResult.hasBlockingIssues {
            throw ExitCode.failure
        }
    }
}
