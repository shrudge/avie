import Foundation
import AvieCore

/// Detects binary targets in the resolved dependency graph by running
/// `swift package dump-package --package-path <path>` for each dependency.
///
/// This is the Option A approach from the architecture review:
/// manifest inspection rather than URL heuristics. A dependency contains
/// a binary target when its own Package.swift declares a `.binaryTarget(...)`.
///
/// The `path` field from `swift package show-dependencies` output gives us
/// the local checkout path for each resolved package. We run dump-package
/// in each checkout directory and check for targets with type "binary".
///
/// Performance: O(N) subprocess calls where N is the number of packages
/// in the graph. For a typical 20-package project this adds ~2–4 seconds.
/// Acceptable for a per-PR diagnostic tool.
public struct BinaryTargetDetector {

    /// Walks the SPM dependency tree and detects which packages contain
    /// `.binaryTarget` declarations in their manifests.
    ///
    /// - Parameters:
    ///   - root: The root SPMDependencyOutput (as returned by SPMResolver.resolve())
    ///   - swiftExecutable: Absolute path to the swift binary (from SwiftToolFinder.path)
    /// - Returns: Set of PackageIdentity values where containsBinaryTarget is true.
    public static func detect(
        in root: SPMDependencyOutput,
        swiftExecutable: String
    ) -> Set<PackageIdentity> {
        var uniquePaths = Set<String>()
        var packageMap = [String: PackageIdentity]()
        
        func flatten(node: SPMDependencyOutput, isRoot: Bool) {
            if !isRoot && !node.path.isEmpty {
                uniquePaths.insert(node.path)
                packageMap[node.path] = identityFromURL(node.url, fallbackName: node.name)
            }
            for dep in node.dependencies {
                flatten(node: dep, isRoot: false)
            }
        }
        flatten(node: root, isRoot: true)
        
        let pathsArray = Array(uniquePaths)
        let lock = NSLock()
        var result = Set<PackageIdentity>()
        
        DispatchQueue.concurrentPerform(iterations: pathsArray.count) { index in
            let path = pathsArray[index]
            if hasBinaryTarget(at: path, swiftExecutable: swiftExecutable) {
                guard let identity = packageMap[path] else { return }
                lock.lock()
                result.insert(identity)
                lock.unlock()
            }
        }
        return result
    }

    /// Runs `swift package dump-package` in the given directory and checks
    /// whether any declared target has type "binary".
    private static func hasBinaryTarget(at packagePath: String, swiftExecutable: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftExecutable)
        // ADDED: --disable-automatic-resolution
        process.arguments = ["package", "--disable-automatic-resolution", "dump-package"]
        process.currentDirectoryURL = URL(fileURLWithPath: packagePath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        guard process.terminationStatus == 0 else { return false }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targets = json["targets"] as? [[String: Any]] else {
            return false
        }

        return targets.contains { target in
            (target["type"] as? String) == "binary"
        }
    }

    /// Derives PackageIdentity from a URL string (last path component, strip .git,
    /// lowercase), with fallback to package name if URL is malformed.
    private static func identityFromURL(_ urlString: String, fallbackName: String) -> PackageIdentity {
        let lastComponent = URL(string: urlString)?.deletingPathExtension().lastPathComponent
            ?? urlString.components(separatedBy: "/").last.map {
                $0.hasSuffix(".git") ? String($0.dropLast(4)) : $0
            } ?? fallbackName
        return PackageIdentity(lastComponent.lowercased())
    }
}
