public struct ResolvedPackage: Identifiable, Hashable, Codable, Sendable {
    public let id: PackageIdentity
    public let url: String
    public let version: String
    public let name: String
    public let directDependencies: [PackageIdentity]
    public let isRoot: Bool
    public let containsBinaryTarget: Bool

    public init(
        id: PackageIdentity,
        url: String,
        version: String,
        name: String,
        directDependencies: [PackageIdentity],
        isRoot: Bool = false,
        containsBinaryTarget: Bool = false
    ) {
        self.id = id
        self.url = url
        self.version = version
        self.name = name
        self.directDependencies = directDependencies
        self.isRoot = isRoot
        self.containsBinaryTarget = containsBinaryTarget
    }
}
