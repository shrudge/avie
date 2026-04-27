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

    public func execute() throws -> [Finding] {
        let context = RuleContext(
            configuration: config,
            targets: targets,
            suppressions: [] // Suppressions handled at output layer
        )

        var allFindings: [Finding] = []
        let enabledRules = instantiateRules(from: config.rules.enabled)

        for rule in enabledRules {
            let findings = try rule.analyze(graph: graph, traversal: traversal, context: context)
            allFindings.append(contentsOf: findings)
        }

        return allFindings
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
