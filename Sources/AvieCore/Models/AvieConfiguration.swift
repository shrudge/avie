public struct AvieConfiguration: Codable, Sendable {
    public var packageDirectory: String = "."
    public var rules: RuleConfiguration = .init()

    public struct RuleConfiguration: Codable, Sendable {
        public var fanoutThreshold: Int = 10
        public var enabled: [RuleID] = [.unreachablePin, .testLeakage,
                                         .excessiveFanout, .binaryTargetIntroduced]
        public var failOn: [RuleID] = [.unreachablePin, .testLeakage,
                                        .binaryTargetIntroduced]
    }

    public var suppressions: [String] = []

    public init() {}
}
