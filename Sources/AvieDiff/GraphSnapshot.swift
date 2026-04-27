import Foundation
import AvieCore

/// A serializable snapshot of a dependency graph state.
/// These are what get compared in PR Diff Mode.
///
/// Snapshots can be:
/// - Generated on the fly from the current working directory
/// - Loaded from a previously saved JSON file (for CI use)
/// - Passed as inline JSON (for GitHub Actions use)
///
/// In CI, the workflow is:
/// 1. On base branch: `avie snapshot --output base-graph.json`
/// 2. On PR branch: `avie snapshot --output head-graph.json`
/// 3. Compare: `avie diff --base base-graph.json --head head-graph.json`
public struct GraphSnapshot: Codable, Sendable {

    /// All packages in this snapshot.
    public let packages: [PackageIdentity: ResolvedPackage]

    /// The root package identity.
    public let rootIdentity: PackageIdentity

    /// All findings from a full audit of this snapshot.
    public let findings: [Finding]

    /// When this snapshot was taken.
    public let capturedAt: Date

    /// The git ref (branch name, commit SHA) this snapshot was taken from.
    /// Optional but strongly recommended for CI traceability.
    public let gitRef: String?

    /// Avie version that generated this snapshot.
    public let avieVersion: String

    public init(
        packages: [PackageIdentity: ResolvedPackage],
        rootIdentity: PackageIdentity,
        findings: [Finding],
        gitRef: String?,
        avieVersion: String
    ) {
        self.packages = packages
        self.rootIdentity = rootIdentity
        self.findings = findings
        self.capturedAt = Date()
        self.gitRef = gitRef
        self.avieVersion = avieVersion
    }

    enum CodingKeys: String, CodingKey {
        case packages
        case rootIdentity
        case findings
        case capturedAt
        case gitRef
        case avieVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode dictionary with String keys, then map to PackageIdentity
        let packagesStringKeyed = try container.decode([String: ResolvedPackage].self, forKey: .packages)
        var decodedPackages: [PackageIdentity: ResolvedPackage] = [:]
        for (key, value) in packagesStringKeyed {
            decodedPackages[PackageIdentity(key)] = value
        }
        self.packages = decodedPackages
        
        self.rootIdentity = try container.decode(PackageIdentity.self, forKey: .rootIdentity)
        self.findings = try container.decode([Finding].self, forKey: .findings)
        self.capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        self.gitRef = try container.decodeIfPresent(String.self, forKey: .gitRef)
        self.avieVersion = try container.decode(String.self, forKey: .avieVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode packages as [String: ResolvedPackage] so JSONEncoder likes it
        var packagesStringKeyed: [String: ResolvedPackage] = [:]
        for (key, value) in self.packages {
            packagesStringKeyed[key.value] = value
        }
        try container.encode(packagesStringKeyed, forKey: .packages)
        
        try container.encode(self.rootIdentity, forKey: .rootIdentity)
        try container.encode(self.findings, forKey: .findings)
        try container.encode(self.capturedAt, forKey: .capturedAt)
        try container.encode(self.gitRef, forKey: .gitRef)
        try container.encode(self.avieVersion, forKey: .avieVersion)
    }
}
