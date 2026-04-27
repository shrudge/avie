public enum RuleID: String, Codable, Sendable, CaseIterable {
    case unreachablePin = "AVIE001"
    case testLeakage = "AVIE002"
    case excessiveFanout = "AVIE003"
    case binaryTargetIntroduced = "AVIE004"
}
