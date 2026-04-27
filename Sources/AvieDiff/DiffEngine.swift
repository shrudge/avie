import AvieCore
import AvieGraph
import AvieRules

/// Computes the structural difference between two dependency graph snapshots.
///
/// The DiffEngine answers these questions:
/// 1. What packages were added in the PR?
/// 2. What packages were removed?
/// 3. Which packages had their version changed?
/// 4. How did the transitive depth change?
/// 5. What NEW findings appear in the PR that didn't exist in base?
/// 6. Were any binary targets introduced?
public final class DiffEngine {

    public struct DiffResult {

        // Packages present in head but not in base
        public let addedPackages: [ResolvedPackage]

        // Packages present in base but not in head
        public let removedPackages: [ResolvedPackage]

        // Packages present in both but with different versions
        public let versionChanges: [VersionChange]

        // New direct dependencies (added to root's direct deps)
        public let newDirectDependencies: [ResolvedPackage]

        // For each new direct dependency: how many transitive deps it introduces
        public let transitiveFanoutByNewDep: [PackageIdentity: Int]

        // New binary targets introduced
        public let newBinaryTargets: [ResolvedPackage]

        // Findings in head that do not exist in base (new violations)
        public let newFindings: [Finding]

        // Findings in base that do not exist in head (resolved violations)
        public let resolvedFindings: [Finding]

        // Change in total transitive depth
        public let depthDelta: Int

        // Change in total package count
        public let packageCountDelta: Int

        public var hasBlockingIssues: Bool {
            !newBinaryTargets.isEmpty ||
            newFindings.contains { $0.severity == .error }
        }
    }

    public struct VersionChange {
        public let package: PackageIdentity
        public let fromVersion: String
        public let toVersion: String
        public let isUpgrade: Bool  // simple string comparison
    }

    public init() {}

    public func diff(base: GraphSnapshot, head: GraphSnapshot) -> DiffResult {
        let baseIDs = Set(base.packages.keys)
        let headIDs = Set(head.packages.keys)

        let addedIDs = headIDs.subtracting(baseIDs)
        let removedIDs = baseIDs.subtracting(headIDs)
        let commonIDs = baseIDs.intersection(headIDs)

        let addedPackages = addedIDs.compactMap { head.packages[$0] }
        let removedPackages = removedIDs.compactMap { base.packages[$0] }

        let versionChanges: [VersionChange] = commonIDs.compactMap { id in
            guard let basePkg = base.packages[id],
                  let headPkg = head.packages[id],
                  basePkg.version != headPkg.version else { return nil }
            return VersionChange(
                package: id,
                fromVersion: basePkg.version,
                toVersion: headPkg.version,
                isUpgrade: headPkg.version > basePkg.version
            )
        }

        // New direct dependencies
        let baseRootDeps = Set(base.packages[base.rootIdentity]?.directDependencies ?? [])
        let headRootDeps = Set(head.packages[head.rootIdentity]?.directDependencies ?? [])
        let newDirectDepIDs = headRootDeps.subtracting(baseRootDeps)
        let newDirectDeps = newDirectDepIDs.compactMap { head.packages[$0] }

        // Transitive fan-out for new direct deps
        var fanout: [PackageIdentity: Int] = [:]
        if let headGraph = try? DependencyGraph(packages: head.packages) {
            let traversal = GraphTraversal(graph: headGraph)
            for depID in newDirectDepIDs {
                fanout[depID] = traversal.allTransitiveDependencies(of: depID).count
            }
        }

        // New binary targets
        let baseBinaryIDs = Set(base.packages.values.filter(\.containsBinaryTarget).map(\.id))
        let headBinaryIDs = Set(head.packages.values.filter(\.containsBinaryTarget).map(\.id))
        let newBinaryTargets = headBinaryIDs.subtracting(baseBinaryIDs)
            .compactMap { head.packages[$0] }

        // New/resolved findings
        let baseFindingKeys = Set(base.findings.map { "\($0.ruleID.rawValue):\($0.affectedPackage.value)" })
        let headFindingKeys = Set(head.findings.map { "\($0.ruleID.rawValue):\($0.affectedPackage.value)" })

        let newFindings = head.findings.filter { finding in
            !baseFindingKeys.contains("\(finding.ruleID.rawValue):\(finding.affectedPackage.value)")
        }
        let resolvedFindings = base.findings.filter { finding in
            !headFindingKeys.contains("\(finding.ruleID.rawValue):\(finding.affectedPackage.value)")
        }

        // Depth delta
        let baseDepth = (try? DependencyGraph(packages: base.packages)).map {
            GraphTraversal(graph: $0).maximumDepth(from: base.rootIdentity)
        } ?? 0
        let headDepth = (try? DependencyGraph(packages: head.packages)).map {
            GraphTraversal(graph: $0).maximumDepth(from: head.rootIdentity)
        } ?? 0

        return DiffResult(
            addedPackages: addedPackages.sorted { $0.name < $1.name },
            removedPackages: removedPackages.sorted { $0.name < $1.name },
            versionChanges: versionChanges,
            newDirectDependencies: newDirectDeps,
            transitiveFanoutByNewDep: fanout,
            newBinaryTargets: newBinaryTargets,
            newFindings: newFindings,
            resolvedFindings: resolvedFindings,
            depthDelta: headDepth - baseDepth,
            packageCountDelta: head.packages.count - base.packages.count
        )
    }
}
