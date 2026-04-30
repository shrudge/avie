import Foundation
import AvieCore
import AvieGraph

public struct RuleEngine {
    public let graph: DependencyGraph
    public let traversal: GraphTraversal
    public let config: AvieConfiguration
    public let targets: [TargetDeclaration]?
    public let suppressions: Set<String>

    public init(
        graph: DependencyGraph,
        config: AvieConfiguration,
        targets: [TargetDeclaration]? = nil,
        suppressions: Set<String> = []
    ) {
        self.graph = graph
        self.traversal = GraphTraversal(graph: graph)
        self.config = config
        self.targets = targets
        self.suppressions = suppressions
    }

    public struct AnalysisResult {
        public let findings: [Finding]
        public let executedRules: [RuleID]
        public let skippedRules: [RuleID: String]
        public let graph: DependencyGraph
        public let metadata: Metadata

        public init(findings: [Finding], executedRules: [RuleID], skippedRules: [RuleID: String], graph: DependencyGraph, metadata: Metadata) {
            self.findings = findings
            self.executedRules = executedRules
            self.skippedRules = skippedRules
            self.graph = graph
            self.metadata = metadata
        }

        public struct Metadata: Codable {
            public let totalPackages: Int
            public let directDependencies: Int
            public let transitiveDepth: Int
            public let analysisDate: Date
            public let packageDirectory: String

            public init(totalPackages: Int, directDependencies: Int, transitiveDepth: Int, analysisDate: Date, packageDirectory: String) {
                self.totalPackages = totalPackages
                self.directDependencies = directDependencies
                self.transitiveDepth = transitiveDepth
                self.analysisDate = analysisDate
                self.packageDirectory = packageDirectory
            }
        }
    }

    public func execute() throws -> AnalysisResult {
        let context = RuleContext(
            configuration: config,
            targets: targets,
            suppressions: suppressions
        )

        var allFindings: [Finding] = []
        var executed: [RuleID] = []
        var skipped: [RuleID: String] = [:]
        
        let enabledRules = instantiateRules(from: config.rules.enabled)

        for rule in enabledRules {
            // Explicitly handle rules that require manifest data
            if rule.id == .testLeakage && targets == nil {
                skipped[.testLeakage] = "Manifest data unavailable (dump-package failed)"
                continue
            }
            
            let findings = try rule.analyze(graph: graph, traversal: traversal, context: context)
            allFindings.append(contentsOf: findings)
            executed.append(rule.id)
        }

        let depth = traversal.maximumDepth(from: graph.rootIdentity)
        let directDeps = (graph.adjacency[graph.rootIdentity] ?? []).count

        // Filter out suppressed findings
        let filteredFindings = allFindings.filter { !suppressions.contains($0.suppressionKey) }

        return AnalysisResult(
            findings: filteredFindings,
            executedRules: executed,
            skippedRules: skipped,
            graph: graph,
            metadata: AnalysisResult.Metadata(
                totalPackages: graph.packages.count,
                directDependencies: directDeps,
                transitiveDepth: depth,
                analysisDate: Date(),
                packageDirectory: config.packageDirectory
            )
        )
    }

    private func instantiateRules(from ids: [RuleID]) -> [Rule] {
        var rules: [Rule] = []
        for id in ids {
            switch id {
            case .unreachablePin:
                rules.append(UnreachablePinRule())
            case .testLeakage:
                rules.append(TestLeakageRule())
            case .excessiveFanout:
                rules.append(ExcessiveFanoutRule())
            case .binaryTargetIntroduced:
                rules.append(BinaryTargetRule())
            }
        }
        return rules
    }
}
