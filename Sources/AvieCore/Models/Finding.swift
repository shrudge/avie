import Foundation

public struct Finding: Identifiable, Codable, Sendable {
    public let id: UUID
    public let ruleID: RuleID

    public enum Severity: String, Codable, Sendable, CaseIterable {
        case error
        case warning
        case note
    }

    public let severity: Severity

    public enum Confidence: String, Codable, Sendable {
        case proven
        case heuristic
        case advisory
    }

    public let confidence: Confidence
    public let summary: String
    public let detail: String
    public let graphPath: [PackageIdentity]
    public let suggestedAction: String
    public let affectedPackage: PackageIdentity

    public var suppressionKey: String {
        "\(ruleID.rawValue):\(affectedPackage.value)"
    }

    public init(
        id: UUID = UUID(),
        ruleID: RuleID,
        severity: Severity,
        confidence: Confidence,
        summary: String,
        detail: String,
        graphPath: [PackageIdentity],
        suggestedAction: String,
        affectedPackage: PackageIdentity
    ) {
        self.id = id
        self.ruleID = ruleID
        self.severity = severity
        self.confidence = confidence
        self.summary = summary
        self.detail = detail
        self.graphPath = graphPath
        self.suggestedAction = suggestedAction
        self.affectedPackage = affectedPackage
    }
}
