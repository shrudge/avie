import Foundation
import AvieCore

/// Converts the recursive SPMDependencyOutput tree into a flat dictionary
/// of ResolvedPackage domain objects with explicit edges.
///
/// Bug 5 Fix: Identity is derived from the package URL (last path component,
/// stripped of .git suffix, lowercased) — NOT from node.name.
/// node.name is the declared display name (e.g. "ArgumentParser") which
/// often differs from the identity used in Package.resolved and dump-package
/// output (e.g. "swift-argument-parser"). Using URL-derived identity ensures
/// cross-referencing works correctly.
///
/// Bug 4 Fix: Accepts a set of known binary target package identities so that
/// containsBinaryTarget is set correctly on each ResolvedPackage.
public struct DependencyTransformer {
    public init() {}

    /// Transform the SPM dependency tree into a flat package dictionary.
    ///
    /// - Parameters:
    ///   - root: Root node from `swift package show-dependencies --format json`
    ///   - binaryTargetIDs: Package identities known to contain binary targets.
    ///     Pass an empty set if binary target detection was skipped.
    public func transform(
        _ root: SPMDependencyOutput,
        binaryTargetIDs: Set<PackageIdentity> = []
    ) -> [PackageIdentity: ResolvedPackage] {
        var packages: [PackageIdentity: ResolvedPackage] = [:]
        transformRecursive(root, isRoot: true, binaryTargetIDs: binaryTargetIDs, into: &packages)
        return packages
    }

    private func transformRecursive(
        _ node: SPMDependencyOutput,
        isRoot: Bool,
        binaryTargetIDs: Set<PackageIdentity>,
        into packages: inout [PackageIdentity: ResolvedPackage]
    ) {
        let identity = identityFromURL(node.url, fallbackName: node.name)

        // Avoid processing the same package twice (diamond dependencies)
        guard packages[identity] == nil else { return }

        // Derive direct dependency IDs from URLs (not names) for consistency
        let directDepIDs = node.dependencies.map { dep in
            identityFromURL(dep.url, fallbackName: dep.name)
        }

        let resolved = ResolvedPackage(
            id: identity,
            url: node.url,
            version: node.version,
            name: node.name,
            directDependencies: directDepIDs,
            isRoot: isRoot,
            containsBinaryTarget: binaryTargetIDs.contains(identity)
        )

        packages[identity] = resolved

        for dep in node.dependencies {
            transformRecursive(dep, isRoot: false, binaryTargetIDs: binaryTargetIDs, into: &packages)
        }
    }

    /// Derives a stable PackageIdentity from a URL string.
    ///
    /// Examples:
    ///   "https://github.com/apple/swift-argument-parser.git" → "swift-argument-parser"
    ///   "https://github.com/groue/GRDB.swift"               → "grdb.swift"
    ///   "file:///root"                                       → "root"  (local root package)
    private func identityFromURL(_ urlString: String, fallbackName: String) -> PackageIdentity {
        guard let url = URL(string: urlString) else {
            return PackageIdentity(fallbackName)
        }
        var lastComponent = url.lastPathComponent
        if lastComponent.hasSuffix(".git") {
            lastComponent = String(lastComponent.dropLast(4))
        }
        let identity = lastComponent.isEmpty ? fallbackName : lastComponent
        return PackageIdentity(identity)
    }
}
