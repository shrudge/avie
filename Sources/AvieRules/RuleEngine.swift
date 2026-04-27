import AvieCore
import AvieGraph

public struct RuleEngine {
    public let graph: DependencyGraph
    public let traversal: GraphTraversal
    public let config: AvieConfiguration
    public let targets: [TargetDeclaration]?

    public init(
        graph: DependencyGraph,
        config: AvieConfiguration,
        targets: [TargetDeclaration]? = nil
    ) {
        self.graph = graph
        self.traversal = GraphTraversal(graph: graph)
        self.config = config
        self.targets = targets
    }

    public struct AnalysisResult {
        public let findings: [Finding]
        public let graph: DependencyGraph
        public let metadata: Metadata

        public struct Metadata: Codable {
            public let totalPackages: Int
            public let directDependencies: Int
            public let transitiveDepth: Int
        }
    }

    public func execute() throws -> AnalysisResult {
        let context = RuleContext(
            configuration: config,
            targets: targets,
            suppressions: [] 
        )

        var allFindings: [Finding] = []
        let enabledRules = instantiateRules(from: config.rules.enabled)

        for rule in enabledRules {
            let findings = try rule.analyze(graph: graph, traversal: traversal, context: context)
            allFindings.append(contentsOf: findings)
        }

        let depth = traversal.maximumDepth(from: graph.rootIdentity)
        let directDeps = (graph.adjacency[graph.rootIdentity] ?? []).count

        return AnalysisResult(
            findings: allFindings,
            graph: graph,
            metadata: AnalysisResult.Metadata(
                totalPackages: graph.packages.count,
                directDependencies: directDeps,
                transitiveDepth: depth
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
