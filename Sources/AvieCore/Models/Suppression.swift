public struct Suppression: Codable, Sendable {
    public let key: String
    public let reason: String
    public let addedBy: String
    public let addedAt: String
}

public struct SuppressionFile: Codable, Sendable {
    public var suppressions: [Suppression] = []

    public static let fileName = "avie-suppress.json"

    public init() {}
}
