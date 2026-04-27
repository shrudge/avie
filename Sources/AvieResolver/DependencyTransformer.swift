import AvieCore

public struct DependencyTransformer {
    public init() {}

    public func transform(_ root: SPMDependencyOutput) -> [PackageIdentity: ResolvedPackage] {
        var packages: [PackageIdentity: ResolvedPackage] = [:]
        transformRecursive(root, isRoot: true, into: &packages)
        return packages
    }

    private func transformRecursive(
        _ node: SPMDependencyOutput,
        isRoot: Bool,
        into packages: inout [PackageIdentity: ResolvedPackage]
    ) {
        let identity = PackageIdentity(node.name)

        guard packages[identity] == nil else { return }

        let directDepIDs = node.dependencies.map { PackageIdentity($0.name) }

        let resolved = ResolvedPackage(
            id: identity,
            url: node.url,
            version: node.version,
            name: node.name,
            directDependencies: directDepIDs,
            isRoot: isRoot,
            containsBinaryTarget: false
        )

        packages[identity] = resolved

        for dep in node.dependencies {
            transformRecursive(dep, isRoot: false, into: &packages)
        }
    }
}
