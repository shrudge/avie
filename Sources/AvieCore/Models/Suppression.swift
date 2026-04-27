import Foundation

public struct Suppression: Codable, Sendable {
    public let key: String
    public let reason: String
    public let addedBy: String
    public let addedAt: String

    public init(key: String, reason: String, addedBy: String, addedAt: String) {
        self.key = key
        self.reason = reason
        self.addedBy = addedBy
        self.addedAt = addedAt
    }
}

public struct SuppressionFile: Codable, Sendable {
    public var suppressions: [Suppression] = []

    public static let fileName = "avie-suppress.json"

    public init() {}

    public static func load(from directory: URL) throws -> SuppressionFile {
        let fileURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return SuppressionFile()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(SuppressionFile.self, from: data)
    }

    public func save(to directory: URL) throws {
        let fileURL = directory.appendingPathComponent(Self.fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: fileURL, options: .atomic)
    }
}

public func applySuppression(_ findings: [Finding], suppressions: SuppressionFile) -> [Finding] {
    let keys = Set(suppressions.suppressions.map(\.key))
    return findings.filter { !keys.contains($0.suppressionKey) }
}
