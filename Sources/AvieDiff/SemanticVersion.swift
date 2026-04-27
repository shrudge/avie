/// Parses and compares semantic version strings numerically.
///
/// Bug 9 Fix: DiffEngine previously used string comparison for isUpgrade
/// ("2.0.0" > "10.0.0" is true in string comparison, incorrect for semver).
/// This type parses version strings into (major, minor, patch) tuples and
/// compares them numerically. Pre-release identifiers (e.g. 1.0.0-beta)
/// are supported: a version with a pre-release suffix is always considered
/// older than the same version without one.
public struct SemanticVersion: Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Non-nil if the version has a pre-release suffix (e.g. "-beta.1")
    public let prerelease: String?

    public var description: String {
        var s = "\(major).\(minor).\(patch)"
        if let pre = prerelease { s += "-\(pre)" }
        return s
    }

    /// Parses a version string. Returns nil if parsing fails entirely.
    public init?(_ string: String) {
        // Strip leading "v" prefix if present
        let s = string.hasPrefix("v") ? String(string.dropFirst()) : string

        // Split off pre-release suffix (after first -)
        let parts = s.split(separator: "-", maxSplits: 1)
        let versionPart = String(parts[0])
        self.prerelease = parts.count > 1 ? String(parts[1]) : nil

        let components = versionPart.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 1 else { return nil }

        self.major = Int(components[0]) ?? 0
        self.minor = components.count >= 2 ? Int(components[1]) ?? 0 : 0
        self.patch = components.count >= 3 ? Int(components[2]) ?? 0 : 0
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Pre-release ordering: 1.0.0-alpha < 1.0.0
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):    return false
        case (nil, _):      return false // no prerelease ≥ prerelease
        case (_, nil):      return true  // prerelease < no prerelease
        case (let l?, let r?): return l < r // lexicographic for pre-release identifiers
        }
    }

    /// Whether this version represents a numeric upgrade from `other`.
    /// Returns false if either version cannot be parsed as semantic.
    public static func isUpgrade(from other: SemanticVersion, to candidate: SemanticVersion) -> Bool {
        return candidate > other
    }
}
