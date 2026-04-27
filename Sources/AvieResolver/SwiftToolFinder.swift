import Foundation

/// Resolves the `swift` executable path at runtime rather than hardcoding /usr/bin/swift.
///
/// Hardcoding /usr/bin/swift breaks on:
/// - Homebrew Swift installations
/// - Xcode-select alternate toolchains
/// - Non-standard CI images
/// - Future Linux support
///
/// Resolution order:
/// 1. `xcrun -f swift` (macOS — handles Xcode-select toolchain correctly)
/// 2. `which swift`   (PATH-based fallback, works on Linux too)
/// 3. `/usr/bin/swift` (last resort hardcoded fallback)
public struct SwiftToolFinder {

    /// The resolved absolute path to the `swift` executable.
    /// Evaluated once at first access and cached.
    public static let path: String = resolveSwiftPath()

    private static func resolveSwiftPath() -> String {
        // Try xcrun first (macOS, respects xcode-select)
        if let xcrunPath = run(executable: "/usr/bin/xcrun", arguments: ["-f", "swift"]) {
            let trimmed = xcrunPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && FileManager.default.fileExists(atPath: trimmed) {
                return trimmed
            }
        }

        // Try which swift (works anywhere swift is on PATH)
        if let whichPath = run(executable: "/usr/bin/which", arguments: ["swift"])
            ?? run(executable: "/bin/which", arguments: ["swift"]) {
            let trimmed = whichPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && FileManager.default.fileExists(atPath: trimmed) {
                return trimmed
            }
        }

        // Final fallback
        return "/usr/bin/swift"
    }

    private static func run(executable: String, arguments: [String]) -> String? {
        guard FileManager.default.fileExists(atPath: executable) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // discard stderr

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
