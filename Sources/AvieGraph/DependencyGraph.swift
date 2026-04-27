import AvieCore

public final class DependencyGraph {
    public let packages: [PackageIdentity: ResolvedPackage]
    public let adjacency: [PackageIdentity: [PackageIdentity]]
    public let reverseAdjacency: [PackageIdentity: [PackageIdentity]]
    public let rootIdentity: PackageIdentity

    public init(packages: [PackageIdentity: ResolvedPackage]) throws {
        guard let root = packages.values.first(where: { $0.isRoot }) else {
            throw GraphError.noRootPackageFound
        }

        self.packages = packages
        self.rootIdentity = root.id

        var adj: [PackageIdentity: [PackageIdentity]] = [:]
        var rev: [PackageIdentity: [PackageIdentity]] = [:]

        for package in packages.values {
            adj[package.id] = package.directDependencies
            for dep in package.directDependencies {
                rev[dep, default: []].append(package.id)
            }
        }

        self.adjacency = adj
        self.reverseAdjacency = rev
    }

    public enum GraphError: Error {
        case noRootPackageFound
    }
}
