import ArgumentParser
import Foundation
import AvieCore
import AvieResolver
import AvieGraph
import AvieRules
import AvieOutput

struct AuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Run a full dependency graph audit."
    )

    @Option(name: .shortAndLong, help: "Path to package directory")
    var path: String = "."

    @Flag(name: .long, help: "CI mode: disable network resolution")
    var ci: Bool = false

    @Option(name: .long, help: "Output format (terminal, json, sarif)")
    var format: String = "terminal"

    mutating func run() throws {
        let packageURL = URL(fileURLWithPath: path).standardized

        let resolver = SPMResolver(packageDirectory: packageURL, isCI: ci)
        try resolver.validate()

        let spmOutput = try resolver.resolve()
        let packages = DependencyTransformer().transform(spmOutput)

        let graph = try DependencyGraph(packages: packages)
        
        let manifestReader = ManifestReader(packageDirectory: packageURL)
        let manifestData = try? manifestReader.read() // Graceful failure if parse fails
        
        let config = (try? ConfigurationLoader.load(from: packageURL)) ?? AvieConfiguration()
        var targets: [TargetDeclaration]? = nil
        
        if let data = manifestData {
            targets = data.targets.map { targetData in
                TargetDeclaration(
                    id: targetData.name,
                    kind: targetKind(from: targetData.type),
                    packageIdentity: graph.rootIdentity,
                    packageDependencies: targetData.dependencies.compactMap { dep in
                        dep.product?.package.lowercased()
                    }.map(PackageIdentity.init)
                )
            }
        }

        let engine = RuleEngine(graph: graph, config: config, targets: targets)
        let allFindings = try engine.execute()

        let suppressionFile = (try? SuppressionFile.load(from: packageURL)) ?? SuppressionFile()
        let filteredFindings = applySuppression(allFindings, suppressions: suppressionFile)

        let formatter: OutputFormatter
        switch format.lowercased() {
        case "json":
            formatter = JSONFormatter()
        case "sarif":
            formatter = SARIFFormatter()
        case "terminal":
            formatter = TerminalFormatter()
        default:
            print("Unknown format: \(format). Falling back to terminal.")
            formatter = TerminalFormatter()
        }

        let output = try formatter.format(filteredFindings)
        print(output)

        let errorRuleIDs = Set(config.rules.failOn)
        let hasFailingErrors = filteredFindings.contains { finding in
            finding.severity == .error && errorRuleIDs.contains(finding.ruleID)
        }

        if hasFailingErrors {
            throw ExitCode.failure
        }
    }
    
    private func targetKind(from typeString: String) -> TargetDeclaration.TargetKind {
        switch typeString {
        case "executable": return .executable
        case "test": return .test
        case "plugin": return .plugin
        case "macro": return .macro
        case "system": return .system
        default: return .regular
        }
    }
}
