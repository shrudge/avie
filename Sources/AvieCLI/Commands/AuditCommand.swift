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

    @Option(name: .long, help: "Output format (terminal, json, sarif)")
    var format: String = "terminal"

    @Flag(name: .long, help: "CI mode: disable network resolution")
    var ci: Bool = false

    @Flag(name: .long, help: "Skip binary target detection (fast mode)")
    var skipBinaryDetection: Bool = false

    @Flag(name: .long, help: "Disable color output")
    var noColor: Bool = false

    @Flag(name: .long, help: "Exit 0 even if error-severity findings are present")
    var noFail: Bool = false

    mutating func run() throws {
        let packageURL = URL(fileURLWithPath: path).standardized

        // Exit 2 — fatal resolver/environment error
        let resolver = SPMResolver(packageDirectory: packageURL, isCI: ci)
        do {
            try resolver.validate()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            throw ExitCode(2)
        }

        let spmOutput: SPMDependencyOutput
        do {
            spmOutput = try resolver.resolve()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            throw ExitCode(2)
        }

        let binaryTargetIDs: Set<PackageIdentity>
        if skipBinaryDetection {
            binaryTargetIDs = []
        } else {
            // Bug 4: Detect binary targets via manifest inspection (Option A).
            // Runs dump-package in each dependency's checkout path.
            binaryTargetIDs = BinaryTargetDetector.detect(
                in: spmOutput,
                swiftExecutable: SwiftToolFinder.path
            )
        }

        // Bug 5: DependencyTransformer now uses URL-derived identity.
        let packages = DependencyTransformer().transform(spmOutput, binaryTargetIDs: binaryTargetIDs)

        let graph: DependencyGraph
        do {
            graph = try DependencyGraph(packages: packages)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            throw ExitCode(2)
        }

        let manifestReader = ManifestReader(packageDirectory: packageURL, isCI: ci)
        let manifestData = try? manifestReader.read()
        
        // Log warning if manifest reading failed
        if manifestData == nil {
            fputs("warning: Failed to read Package.swift manifest. Some rules will be skipped.\n", stderr)
        }

        // Exit 3 — configuration error
        let config: AvieConfiguration
        do {
            config = try ConfigurationLoader.load(from: packageURL)
        } catch {
            fputs("error: .avie.json is malformed — \(error.localizedDescription)\n", stderr)
            throw ExitCode(3)
        }

        let targets = manifestData.map { buildTargets(from: $0, rootIdentity: graph.rootIdentity) }

        // Load suppressions and pass to RuleContext
        let suppressionFile = (try? SuppressionFile.load(from: packageURL)) ?? SuppressionFile()
        let suppressionKeys = Set(suppressionFile.suppressions.map(\.key))

        let engine = RuleEngine(graph: graph, config: config, targets: targets, suppressions: suppressionKeys)
        let analysisResult = try engine.execute()
        
        // Apply suppressions (should already be filtered by engine, but apply again for safety)
        let filteredFindings = applySuppression(analysisResult.findings, suppressions: suppressionFile)
        
        // Rebuild the result with filtered findings
        let finalResult = RuleEngine.AnalysisResult(
            findings: filteredFindings,
            executedRules: analysisResult.executedRules,
            skippedRules: analysisResult.skippedRules,
            graph: analysisResult.graph,
            metadata: analysisResult.metadata
        )

        let formatter: OutputFormatter
        switch format.lowercased() {
        case "json":
            formatter = JSONFormatter()
        case "sarif":
            formatter = SARIFFormatter()
        default:
            formatter = TerminalFormatter(useColor: !noColor)
        }

        let output = try formatter.format(finalResult)
        print(output)

        guard !noFail else { return }

        // Exit 1 — error-severity findings on a configured failOn rule
        let errorRuleIDs = Set(config.rules.failOn)
        let hasFailingErrors = filteredFindings.contains { finding in
            finding.severity == .error && errorRuleIDs.contains(finding.ruleID)
        }

        if hasFailingErrors {
            throw ExitCode(1)
        }
    }
}
