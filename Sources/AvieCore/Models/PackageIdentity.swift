import Foundation

public struct PackageIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
            .lowercased()
            .replacingOccurrences(of: ".git", with: "")
    }

    public var description: String { value }
}
