import AvieCore
import AvieGraph

public protocol Rule {
    var id: RuleID { get }
    var severity: Finding.Severity { get }
    var name: String { get }
    var description: String { get }

    func analyze(
        graph: DependencyGraph,
        traversal: GraphTraversal,
        context: RuleContext
    ) throws -> [Finding]
}

public struct RuleContext {
    public let configuration: AvieConfiguration
    public let targets: [TargetDeclaration]?
    public let suppressions: Set<String>

    public init(
        configuration: AvieConfiguration,
        targets: [TargetDeclaration]?,
        suppressions: Set<String>
    ) {
        self.configuration = configuration
        self.targets = targets
        self.suppressions = suppressions
    }
}
