import ArgumentParser
import Foundation
import AvieCore
import AvieResolver
import AvieGraph
import AvieRules
import AvieDiff

struct SnapshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Capture the current dependency graph as a JSON snapshot for PR diff comparison."
    )

    @Option(name: .shortAndLong, help: "Path to package directory")
    var path: String = "."

    @Option(name: .shortAndLong, help: "Output file path for the snapshot JSON")
    var output: String = "avie-snapshot.json"

    @Option(name: .long, help: "Git ref label for this snapshot (e.g. branch name)")
    var gitRef: String?
    
    @Flag(name: .long, help: "CI mode: disable network resolution")
    var ci: Bool = false

    @Flag(name: .long, help: "Skip binary target detection (fast mode)")
    var skipBinaryDetection: Bool = false

    mutating func run() throws {
        let packageURL = URL(fileURLWithPath: path).standardized

        // 1. Validate
        let resolver = SPMResolver(packageDirectory: packageURL, isCI: ci)
        try resolver.validate()

        // 2. Resolve
        let spmOutput = try resolver.resolve()

        let binaryTargetIDs: Set<PackageIdentity>
        if skipBinaryDetection {
            binaryTargetIDs = []
        } else {
            // Bug 4: Detect binary targets via manifest inspection in each checkout.
            binaryTargetIDs = BinaryTargetDetector.detect(
                in: spmOutput,
                swiftExecutable: SwiftToolFinder.path
            )
        }

        // Bug 5: URL-derived identity via updated DependencyTransformer.
        let packages = DependencyTransformer().transform(spmOutput, binaryTargetIDs: binaryTargetIDs)

        // 3. Optional Manifest for richer analysis
        let manifestReader = ManifestReader(packageDirectory: packageURL, isCI: ci)
        let manifestData = try? manifestReader.read()

        // 4. Build graph
        let graph = try DependencyGraph(packages: packages)

        // 5. Config/Targets
        let config = (try? ConfigurationLoader.load(from: packageURL)) ?? AvieConfiguration()
        let targets = manifestData.map { buildTargets(from: $0, rootIdentity: graph.rootIdentity) }

        // 6. Run Rules
        let engine = RuleEngine(graph: graph, config: config, targets: targets)
        let analysisResult = try engine.execute()
        
        // 7. Filter Suppressions
        let suppressionFile = (try? SuppressionFile.load(from: packageURL)) ?? SuppressionFile()
        let filteredFindings = applySuppression(analysisResult.findings, suppressions: suppressionFile)

        // 8. Serialize Snapshot
        let snapshot = GraphSnapshot(
            packages: packages,
            rootIdentity: graph.rootIdentity,
            findings: filteredFindings,
            gitRef: gitRef,
            avieVersion: avieToolVersion
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(snapshot)
        try data.write(to: URL(fileURLWithPath: output))

        print("Snapshot written to \(output)")
    }
    
}
