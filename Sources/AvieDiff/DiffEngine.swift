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
}
