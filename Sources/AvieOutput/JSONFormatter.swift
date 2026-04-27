import Foundation
import AvieCore

public struct JSONFormatter: OutputFormatter {
    public init() {}

    public func format(_ findings: [Finding]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        // Findings is already Codable, so encode directly
        let data = try encoder.encode(findings)
        guard let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}
