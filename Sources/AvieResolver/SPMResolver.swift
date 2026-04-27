import Foundation
import AvieCore

/// Executes `swift package show-dependencies --format json` and parses
/// the output into Avie's domain model.
///
/// Bug 6 Fix: Uses SwiftToolFinder.path instead of hardcoded /usr/bin/swift.
/// This ensures correct toolchain resolution on Homebrew installations,
/// Xcode-select alternate toolchains, and non-standard CI images.
public final class SPMResolver {
    private let packageDirectory: URL
    private let isCI: Bool

    public init(packageDirectory: URL, isCI: Bool = false) {
        self.packageDirectory = packageDirectory
        self.isCI = isCI
    }

    public enum ResolverError: Error, LocalizedError {
        case packageDirectoryNotFound(URL)
        case packageManifestNotFound(URL)
        case xcodeProjectDetected(URL)
        case dependenciesNotResolved(String)
        case commandFailed(exitCode: Int32, stderr: String)
        case parseError(underlying: Error, rawOutput: String)

        public var errorDescription: String? {
            switch self {
            case .packageDirectoryNotFound(let url):
                return "Package directory not found: \(url.path)"
            case .packageManifestNotFound(let url):
                return """
                No Package.swift found in \(url.path).
                Avie requires a Swift Package Manager project.
                Note: Xcode-managed projects (.xcodeproj) are not supported in v1.
                """
            case .xcodeProjectDetected(let url):
                return """
                An Xcode project was detected at \(url.path).
                Avie v1 supports pure SPM packages only.
                Xcode project support is planned for v2.
                """
            case .dependenciesNotResolved(let hint):
                return """
                Package dependencies are not resolved. Run `swift package resolve` first.
                Hint: \(hint)
                """
            case .commandFailed(let code, let stderr):
                return "swift package show-dependencies failed (exit \(code)):\n\(stderr)"
            case .parseError(let error, _):
                return "Failed to parse dependency output: \(error.localizedDescription)"
            }
        }
    }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: packageDirectory.path) else {
            throw ResolverError.packageDirectoryNotFound(packageDirectory)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: packageDirectory, includingPropertiesForKeys: nil
        )
        let xcodeprojURLs = contents.filter { $0.pathExtension == "xcodeproj" }

        if !xcodeprojURLs.isEmpty {
            throw ResolverError.xcodeProjectDetected(xcodeprojURLs[0])
        }

        let manifestURL = packageDirectory.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ResolverError.packageManifestNotFound(packageDirectory)
        }
    }

    public func resolve() throws -> SPMDependencyOutput {
        var arguments = ["package", "show-dependencies", "--format", "json"]

        if isCI {
            arguments.append("--disable-automatic-resolution")
        }

        let process = Process()
        // Bug 6 Fix: resolve swift from PATH instead of hardcoding /usr/bin/swift
        process.executableURL = URL(fileURLWithPath: SwiftToolFinder.path)
        process.arguments = arguments
        process.currentDirectoryURL = packageDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ResolverError.commandFailed(exitCode: -1, stderr: error.localizedDescription)
        }

        process.waitUntilExit()

        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            if stderrString.contains("not resolved") || stderrString.contains("resolve first") {
                throw ResolverError.dependenciesNotResolved(stderrString)
            }
            throw ResolverError.commandFailed(exitCode: process.terminationStatus,
                                               stderr: stderrString)
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let rawOutput = String(data: outputData, encoding: .utf8) ?? ""

        do {
            let decoded = try JSONDecoder().decode(SPMDependencyOutput.self, from: outputData)
            return decoded
        } catch {
            throw ResolverError.parseError(underlying: error, rawOutput: rawOutput)
        }
    }
}
