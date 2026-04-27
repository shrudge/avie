import PackagePlugin
import Foundation

@main
struct AviePlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let avieTool = try context.tool(named: "avie")
        var processArgs = ["audit", "--path", context.package.directory.string]

        var argExtractor = ArgumentExtractor(arguments)
        if let format = argExtractor.extractOption(named: "format").first {
            processArgs += ["--format", format]
        }
        if argExtractor.extractFlag(named: "ci") > 0 {
            processArgs.append("--ci")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: avieTool.path.string)
        process.arguments = processArgs

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw PluginError.auditFailed(process.terminationStatus)
        }
    }

    enum PluginError: Error {
        case auditFailed(Int32)
    }
}
