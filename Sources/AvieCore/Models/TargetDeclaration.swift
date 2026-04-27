public struct TargetDeclaration: Identifiable, Hashable, Codable, Sendable {
    public let id: String

    public enum TargetKind: String, Codable, Sendable {
        case regular
        case executable
        case test
        case plugin
        case macro
        case system
    }

    public let kind: TargetKind
    public let packageIdentity: PackageIdentity
    public let packageDependencies: [PackageIdentity]

    public var isProduction: Bool {
        switch kind {
        case .regular, .executable, .macro: return true
        case .test, .plugin, .system: return false
        }
    }
}
