import Foundation
import AvieCore
import AvieDiff

public struct JSONFormatter: OutputFormatter {
    public init() {}

    public func format(_ findings: [Finding]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(findings)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public struct DiffReport: Codable {
        public let schemaVersion: String
        public let addedPackages: Set<PackageIdentity>
        public let removedPackages: Set<PackageIdentity>
        public let versionChanges: [PackageIdentity: VersionChangeDTO]
        public let newDirectDependencies: Set<PackageIdentity>
        public let transitiveFanoutByNewDep: [PackageIdentity: Int]
        public let newBinaryTargets: Set<PackageIdentity>
        public let newFindings: [Finding]
        public let resolvedFindings: [Finding]
        public let depthDelta: Int
        public let packageCountDelta: Int
        public let hasBlockingIssues: Bool

        public struct VersionChangeDTO: Codable {
            public let fromVersion: String
            public let toVersion: String
            public let isUpgrade: Bool
        }
    }

    public func format(diff: DiffEngine.DiffResult) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var versionChangesMap: [PackageIdentity: DiffReport.VersionChangeDTO] = [:]
        for vc in diff.versionChanges {
            versionChangesMap[vc.package] = DiffReport.VersionChangeDTO(
                fromVersion: vc.fromVersion,
                toVersion: vc.toVersion,
                isUpgrade: vc.isUpgrade
            )
        }

        let report = DiffReport(
            schemaVersion: "1.0",
            addedPackages: Set(diff.addedPackages.map(\.id)),
            removedPackages: Set(diff.removedPackages.map(\.id)),
            versionChanges: versionChangesMap,
            newDirectDependencies: Set(diff.newDirectDependencies.map(\.id)),
            transitiveFanoutByNewDep: diff.transitiveFanoutByNewDep,
            newBinaryTargets: Set(diff.newBinaryTargets.map(\.id)),
            newFindings: diff.newFindings,
            resolvedFindings: diff.resolvedFindings,
            depthDelta: diff.depthDelta,
            packageCountDelta: diff.packageCountDelta,
            hasBlockingIssues: diff.hasBlockingIssues
        )

        let data = try encoder.encode(report)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
