import Foundation
import AvieCore

/// Parses Package.swift to extract target-level declarations.
/// Uses `swift package dump-package` to leverage SPM's own manifest parser.
///
/// Bug 6 Fix: Uses SwiftToolFinder.path instead of /usr/bin/swift.
///
/// Bug 7 Fix: ManifestTargetDependency handles the real dump-package JSON
/// tagged-union schema. The dump-package output represents each dependency
/// as a single-key object (a discriminated union):
///
///   {"product": ["ProductName", "PackageIdentity", null, null]}
///   {"byName": ["TargetOrPackageName", null]}
///   {"target": ["TargetName"]}
///
/// The previous model used struct keys that only matched one variant.
/// The new model handles all three variants via custom Codable decoding.
    public enum ManifestError: Error, LocalizedError {
        case dumpPackageFailed(String)
        case decodeFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .dumpPackageFailed(let stderr):
                return "swift package dump-package failed:\n\(stderr)"
            case .decodeFailed(let error):
                return "Failed to decode package manifest: \(error.localizedDescription)"
            }
        }
    }

public final class ManifestReader {
    private let packageDirectory: URL
    private let isCI: Bool

    public init(packageDirectory: URL, isCI: Bool = false) {
        self.packageDirectory = packageDirectory
        self.isCI = isCI
    }

    public struct ManifestData: Codable {
        public let name: String
        public let targets: [ManifestTarget]
    }

    public struct ManifestTarget: Codable {
        public let name: String
        /// "regular", "executable", "test", "plugin", "macro", "binary", "system"
        public let type: String
        public let dependencies: [ManifestTargetDependency]
    }

    /// A target-level dependency in dump-package output.
    /// dump-package uses a discriminated union (tagged union) with exactly one
    /// of the following keys present per entry:
    ///   - "product": array [productName, packageIdentity, moduleAliases?, condition?]
    ///   - "byName":  array [name, condition?]
    ///   - "target":  array [targetName]
    public enum ManifestTargetDependency: Codable {
        /// A dependency on a product from an external package.
        /// packageIdentity is the key cross-referenced against graph identities.
        case product(name: String, packageIdentity: String)

        /// A dependency by name — either a target in the same package or an
        /// external package imported by its last path component.
        case byName(String)

        /// A dependency on a target within the same package.
        case target(String)

        // MARK: - Codable

        private enum TopLevelKey: String, CodingKey {
            case product, byName, target
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: TopLevelKey.self)

            if let productArray = try? container.decode([String?].self, forKey: .product) {
                // product: [name, packageIdentity, moduleAliases?, condition?]
                let name = productArray.count > 0 ? productArray[0] ?? "" : ""
                let pkg  = productArray.count > 1 ? productArray[1] ?? "" : ""
                self = .product(name: name, packageIdentity: pkg)
            } else if let byNameArray = try? container.decode([String?].self, forKey: .byName) {
                let name = byNameArray.first ?? nil
                self = .byName(name ?? "")
            } else if let targetArray = try? container.decode([String?].self, forKey: .target) {
                let name = targetArray.first ?? nil
                self = .target(name ?? "")
            } else {
                // Unrecognized variant — skip gracefully
                self = .byName("")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: TopLevelKey.self)
            switch self {
            case .product(let name, let pkg):
                try container.encode([name, pkg], forKey: .product)
            case .byName(let name):
                try container.encode([name], forKey: .byName)
            case .target(let name):
                try container.encode([name], forKey: .target)
            }
        }

        /// Returns the external package identity this dependency refers to, if any.
        /// Used by AVIE002 (Test Leakage) to determine which graph packages
        /// a target depends on.
        public var packageIdentity: String? {
            switch self {
            case .product(_, let pkg): return pkg.isEmpty ? nil : pkg.lowercased()
            case .byName(let name): return name.isEmpty ? nil : name.lowercased()
            case .target: return nil // intra-package, not cross-package
            }
        }
    }

    public func read() throws -> ManifestData {
        let process = Process()
        // Bug 6 Fix: resolve swift from PATH
        process.executableURL = URL(fileURLWithPath: SwiftToolFinder.path)
        var arguments = ["package"]
        if isCI {
            arguments.append("--disable-automatic-resolution")
        }
        arguments.append("dump-package")
        process.arguments = arguments
        process.currentDirectoryURL = packageDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        
        // Drain pipes BEFORE waiting
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(data: stderrData, encoding: .utf8) ?? ""
            throw ManifestError.dumpPackageFailed(err)
        }

        do {
            return try JSONDecoder().decode(ManifestData.self, from: data)
        } catch {
            throw ManifestError.decodeFailed(error)
        }
    }
}
