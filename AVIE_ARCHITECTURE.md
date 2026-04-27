# Avie — Complete Engineering Architecture & Implementation Specification
### The Swift Package Graph Diagnostics Tool
**Version:** 1.0 (Pre-Implementation Master Spec)  
**Audience:** Claude Code + Implementing Developer  
**Status:** Authoritative. Every design decision in this document is final and justified.

---

## Table of Contents

1. [Project Identity & Mandate](#1-project-identity--mandate)
2. [What Avie Is Not (Hard Constraints)](#2-what-avie-is-not-hard-constraints)
3. [Repository & Package Structure](#3-repository--package-structure)
4. [Module Architecture Overview](#4-module-architecture-overview)
5. [Module 1: AvieCore — Domain Model](#5-module-1-aviecore--domain-model)
6. [Module 2: AvieResolver — Graph Ingestion](#6-module-2-avieresolver--graph-ingestion)
7. [Module 3: AvieGraph — Graph Engine](#7-module-3-aviegraph--graph-engine)
8. [Module 4: AvieRules — Analysis Passes](#8-module-4-avierules--analysis-passes)
9. [Module 5: AvieDiff — PR Diff Engine](#9-module-5-aviediff--pr-diff-engine)
10. [Module 6: AvieOutput — Formatters](#10-module-6-avieoutput--formatters)
11. [Module 7: AvieCLI — Entry Point](#11-module-7-aviecli--entry-point)
12. [Module 8: AviePlugin — SPM Command Plugin](#12-module-8-avieplugin--spm-command-plugin)
13. [Cross-Cutting Concerns](#13-cross-cutting-concerns)
14. [Operational Edge Cases (Must Handle Before Ship)](#14-operational-edge-cases-must-handle-before-ship)
15. [Testing Strategy](#15-testing-strategy)
16. [CI/CD & Distribution](#16-cicd--distribution)
17. [Phase Build Order](#17-phase-build-order)
18. [Appendix: Key Design Decisions Log](#18-appendix-key-design-decisions-log)

---

## 1. Project Identity & Mandate

### What Avie Is

Avie is a **Swift package graph diagnostics CLI**. Its job is to analyze the dependency graph of a Swift Package Manager project and surface findings about structural problems — unreachable packages, test dependency leakage into production targets, excessive transitive fan-out, and binary target introductions — with complete confidence about what it is claiming and why.

The single most important property of Avie is **trust**. Every finding Avie emits must be one a developer can immediately understand, verify, and act on. A tool that produces false positives gets disabled. Avie does not produce false positives because its entire ruleset is built on graph mathematics, not heuristics.

### The Problem Being Solved

When iOS and macOS teams scale their projects, their dependency graphs accumulate structural problems:

- Packages that are pinned in `Package.resolved` but no longer reachable from any production target
- Test frameworks (Quick, Nimble, etc.) that are transitively reachable from production targets due to misconfigured target declarations
- Pull requests that silently add a single "lightweight" dependency that actually pulls in 15 transitive packages
- Binary XCFramework targets being introduced without a formal review checkpoint

None of these are caught by the Swift compiler, by SPM's resolver, or by existing CI tooling. SPM prevents *version conflicts* — it does not prevent *structural waste*.

### The Unique Value Proposition

**PR Diff Mode** is Avie's killer feature. The ability to compare the dependency graph of a base branch versus a PR branch — and surface precisely what changed, what was added, and what increased — is what justifies Avie's existence in a CI pipeline. No existing tool in the Swift ecosystem does this cleanly.

**Graph-provable findings** are Avie's trust foundation. Every finding emitted by Avie v1 is derivable purely from graph structure. No source scanning. No heuristics. No "we think this might be unused." Either a node is reachable from the root or it isn't. The math does not lie.

---

## 2. What Avie Is Not (Hard Constraints)

These are not preferences. They are architectural decisions made after deep scrutiny. Claude Code must never deviate from these without explicit human instruction.

### ❌ NOT a source code scanner (in v1)

Avie v1 does **not** scan `.swift` source files for `import` statements. This decision is final for the following reasons:

1. `SwiftSyntax` import detection is heuristic — it cannot handle `@_exported import`, `#if canImport(X)`, `@testable import`, macro-generated usage, or linker-only dependencies. Any tool built on this will produce false positives.
2. `SwiftIndexStore` is accurate but requires a prior successful compilation. Requiring a 20-minute `xcodebuild` run before Avie can execute destroys the Developer Experience that is central to Avie's mandate.
3. The graph-only ruleset covers the highest-value findings already. Source evidence is a v2 feature, explicitly designed as an optional additive layer.

### ❌ NOT a Build Tool Plugin

A Build Tool Plugin runs on every `swift build` and every `Cmd+B` in Xcode. It participates in the build graph. It adds latency to incremental builds that have nothing to do with dependency changes. Any tool that does this gets removed from projects within a week.

Avie ships as a **Command Plugin** (`swift package avie-audit`) and a standalone **CLI binary**. Both are invoked intentionally. Neither ever runs automatically.

### ❌ NOT a "dead dependency" detector

The language Avie uses in all output, documentation, and help text must be precise:

- **Use:** "unreachable," "not reachable from root targets," "excessive fan-out," "test-only package reachable from production target"
- **Never use:** "dead," "unused," "bloat" (in findings), "unnecessary"

The reason: "unused" implies Avie has proven semantic usage. Avie has not. Avie has proven graph reachability. Those are different claims. Using the wrong language exposes Avie to justified criticism and destroys credibility with senior Swift developers.

### ❌ NOT targeting Xcode-managed projects in v1

Xcode projects that use SPM for dependencies but are not pure SPM packages store `Package.resolved` inside:
```
MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

The `swift package show-dependencies` command does not work in these directories. Supporting this requires a separate resolution path. This is explicitly out of scope for v1. The `--project-type` flag is reserved for v2. Document this limitation clearly in `README.md`.

### ❌ NOT claiming "zero false positives"

This phrase must never appear in documentation, help text, or marketing. The correct phrase is **"graph-provable findings."** There is a subtle but critical difference:

- "Zero false positives" is a promise you will eventually break (stale `Package.resolved` pins, for instance, are technically unreachable but are resolver artifacts, not developer mistakes).
- "Graph-provable" accurately describes what Avie does: it makes claims derivable from graph structure, and it can always show you the graph path that justifies the finding.

---

## 3. Repository & Package Structure

```
avie/
├── Package.swift                    # Root manifest, declares all targets
├── README.md
├── CHANGELOG.md
├── Sources/
│   ├── AvieCore/                    # Module 1: Domain model, no dependencies
│   ├── AvieResolver/                # Module 2: Graph ingestion from SPM
│   ├── AvieGraph/                   # Module 3: Graph engine, traversal, algorithms
│   ├── AvieRules/                   # Module 4: Rule definitions and analysis passes
│   ├── AvieDiff/                    # Module 5: PR diff engine
│   ├── AvieOutput/                  # Module 6: Terminal, JSON, SARIF formatters
│   └── AvieCLI/                     # Module 7: main.swift, argument parsing
├── Plugins/
│   └── AviePlugin/                  # Module 8: SPM Command Plugin wrapper
├── Tests/
│   ├── AvieCoreTests/
│   ├── AvieResolverTests/
│   ├── AvieGraphTests/
│   ├── AvieRulesTests/
│   ├── AvieDiffTests/
│   └── AvieOutputTests/
└── Fixtures/
    ├── simple-package/              # Minimal test SPM package
    ├── deep-transitive/             # Package with 10+ transitive deps
    ├── test-leakage/                # Package with test deps in prod targets
    ├── binary-target/               # Package introducing .binaryTarget
    └── unreachable-pin/             # Package with stale pins
```

### `Package.swift` Target Declarations

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "avie",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "avie", targets: ["AvieCLI"]),
        .plugin(name: "AviePlugin", targets: ["AviePlugin"]),
        .library(name: "AvieCore", targets: ["AvieCore"]),   // for testing
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
    ],
    targets: [
        // Core domain model — zero external dependencies
        .target(name: "AvieCore", dependencies: []),

        // Graph ingestion — depends on Core only
        .target(name: "AvieResolver", dependencies: ["AvieCore"]),

        // Graph algorithms — depends on Core only
        .target(name: "AvieGraph", dependencies: ["AvieCore"]),

        // Rule engine — depends on Core, Graph
        .target(name: "AvieRules", dependencies: ["AvieCore", "AvieGraph"]),

        // Diff engine — depends on Core, Graph, Rules
        .target(name: "AvieDiff", dependencies: ["AvieCore", "AvieGraph", "AvieRules"]),

        // Output formatters — depends on Core, Rules, Diff
        .target(name: "AvieOutput", dependencies: ["AvieCore", "AvieRules", "AvieDiff"]),

        // CLI entry point — depends on everything + ArgumentParser
        .executableTarget(
            name: "AvieCLI",
            dependencies: [
                "AvieCore", "AvieResolver", "AvieGraph",
                "AvieRules", "AvieDiff", "AvieOutput",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // SPM Command Plugin
        .plugin(
            name: "AviePlugin",
            capability: .command(
                intent: .custom(verb: "avie-audit", description: "Run Avie dependency graph audit"),
                permissions: [.writeToPackageDirectory(reason: "Write SARIF report")]
            )
        ),

        // Tests
        .testTarget(name: "AvieCoreTests", dependencies: ["AvieCore"]),
        .testTarget(name: "AvieResolverTests", dependencies: ["AvieResolver"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "AvieGraphTests", dependencies: ["AvieGraph"]),
        .testTarget(name: "AvieRulesTests", dependencies: ["AvieRules", "AvieGraph"]),
        .testTarget(name: "AvieDiffTests", dependencies: ["AvieDiff"]),
        .testTarget(name: "AvieOutputTests", dependencies: ["AvieOutput"]),
    ]
)
```

**Dependency Direction Law (never violate this):**

```
AvieCore  ←  AvieResolver
AvieCore  ←  AvieGraph
AvieCore  ←  AvieRules  ←  AvieGraph
AvieCore  ←  AvieDiff   ←  AvieGraph, AvieRules
AvieCore  ←  AvieOutput ←  AvieRules, AvieDiff
AvieCLI   ←  everything
AviePlugin (Plugin target, separate from library targets)
```

Lower-level modules must **never** import higher-level modules. `AvieCore` knows nothing about output formats. `AvieGraph` knows nothing about rules. This ensures every module is independently testable.

---

## 4. Module Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  AvieCLI  (Entry Point, Argument Parsing)                       │
│  AviePlugin  (SPM Command Plugin wrapper)                       │
└──────────────────────┬──────────────────────────────────────────┘
                       │ uses
┌──────────────────────▼──────────────────────────────────────────┐
│  AvieOutput  (Terminal / JSON / SARIF Formatters)               │
└──────────┬───────────────────────┬──────────────────────────────┘
           │ reads                 │ reads
┌──────────▼──────────┐  ┌────────▼────────────────────────────┐
│  AvieRules          │  │  AvieDiff                           │
│  (Analysis Passes)  │  │  (PR Diff Engine)                   │
└──────────┬──────────┘  └────────┬────────────────────────────┘
           │ uses                 │ uses
┌──────────▼──────────────────────▼──────────────────────────────┐
│  AvieGraph  (Graph Engine: DAG, BFS/DFS, Reachability)         │
└──────────────────────┬──────────────────────────────────────────┘
                       │ uses
┌──────────────────────▼──────────────────────────────────────────┐
│  AvieResolver  (SPM Ingestion: show-dependencies wrapper)       │
└──────────────────────┬──────────────────────────────────────────┘
                       │ uses / produces
┌──────────────────────▼──────────────────────────────────────────┐
│  AvieCore  (Domain Model: Package, Product, Target, Finding...) │
│  (Zero external dependencies)                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Module 1: AvieCore — Domain Model

**Location:** `Sources/AvieCore/`  
**External Dependencies:** None  
**Purpose:** Defines every domain type used across all modules. This is the shared language of the entire codebase. Changes here affect everything. Stability of this module is paramount.

### 5.1 Package Identity

```swift
// Sources/AvieCore/Models/PackageIdentity.swift

/// The canonical identifier for a package in the resolved graph.
/// SPM uses URL-derived identity (lowercased last path component without .git).
/// Example: "https://github.com/apple/swift-argument-parser" → "swift-argument-parser"
public struct PackageIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        // Normalize: lowercase, strip .git suffix
        self.value = value
            .lowercased()
            .replacingOccurrences(of: ".git", with: "")
    }

    public var description: String { value }
}
```

### 5.2 Resolved Package

```swift
// Sources/AvieCore/Models/ResolvedPackage.swift

/// Represents a single package as it appears in the resolved dependency graph.
/// This is the primary node type in Avie's graph.
/// Produced by AvieResolver from `swift package show-dependencies` output.
public struct ResolvedPackage: Identifiable, Hashable, Codable, Sendable {
    public let id: PackageIdentity

    /// The canonical URL for this package.
    public let url: String

    /// The resolved version string. May be a semantic version ("1.2.3"),
    /// a branch name ("main"), or a revision hash.
    public let version: String

    /// The package name as declared in the package's own Package.swift.
    /// May differ from identity. Example: identity "swift-argument-parser",
    /// name "ArgumentParser"
    public let name: String

    /// Direct dependencies of this package (their identities).
    /// This is where the graph edges come from — NOT from Package.resolved.
    /// These are populated by AvieResolver from show-dependencies JSON.
    public let directDependencies: [PackageIdentity]

    /// Whether this package is a root package (the project being analyzed)
    public let isRoot: Bool

    /// Whether any declared target is a binary target
    public let containsBinaryTarget: Bool

    public init(
        id: PackageIdentity,
        url: String,
        version: String,
        name: String,
        directDependencies: [PackageIdentity],
        isRoot: Bool = false,
        containsBinaryTarget: Bool = false
    ) {
        self.id = id
        self.url = url
        self.version = version
        self.name = name
        self.directDependencies = directDependencies
        self.isRoot = isRoot
        self.containsBinaryTarget = containsBinaryTarget
    }
}
```

### 5.3 Target Declaration

```swift
// Sources/AvieCore/Models/TargetDeclaration.swift

/// Represents a target as declared in Package.swift.
/// Parsed from the package manifest, NOT from show-dependencies output.
/// This is essential for the Test-Leakage rule.
public struct TargetDeclaration: Identifiable, Hashable, Codable, Sendable {
    public let id: String  // target name

    public enum TargetKind: String, Codable, Sendable {
        case regular        // .target(...)
        case executable     // .executableTarget(...)
        case test           // .testTarget(...)
        case plugin         // .plugin(...)
        case macro          // .macro(...)
        case system         // .systemLibrary(...)
    }

    public let kind: TargetKind
    public let packageIdentity: PackageIdentity

    /// Names of packages this target explicitly depends on.
    /// Populated from Package.swift parsing.
    public let packageDependencies: [PackageIdentity]

    /// Whether this target is considered "production" (ships in App Store binary).
    /// Production = regular + executable + macro
    /// Non-production = test + plugin
    public var isProduction: Bool {
        switch kind {
        case .regular, .executable, .macro: return true
        case .test, .plugin, .system: return false
        }
    }
}
```

### 5.4 Finding (the core output type)

```swift
// Sources/AvieCore/Models/Finding.swift

/// A single diagnostic finding produced by Avie's analysis.
/// Every finding must carry enough information for a developer to:
/// 1. Understand what the problem is
/// 2. See the graph path that proves it
/// 3. Know exactly how to fix it
/// 4. Suppress it if intentional
public struct Finding: Identifiable, Codable, Sendable {
    public let id: UUID

    public let ruleID: RuleID

    public enum Severity: String, Codable, Sendable, CaseIterable {
        case error    // Fails CI by default. Graph-provable violations.
        case warning  // Informational. Does not fail CI by default.
        case note     // Advisory. Context only.
    }

    public let severity: Severity

    /// How confident is Avie in this finding?
    /// In v1, all findings are .proven because we only have graph rules.
    /// Source-evidence rules in v2 will introduce .heuristic.
    public enum Confidence: String, Codable, Sendable {
        case proven       // Derivable purely from graph structure. No source scanning.
        case heuristic    // Requires source evidence. Reserved for v2.
        case advisory     // External metadata (staleness). Reserved for v2.
    }

    public let confidence: Confidence

    /// Human-readable summary of the finding.
    public let summary: String

    /// Full explanation of why this is a problem.
    public let detail: String

    /// The graph path that proves this finding.
    /// For an unreachable package: the set of packages that WAS reachable before.
    /// For test-leakage: the exact path from production target → test package.
    /// This is mandatory. A finding without a graph path will not be trusted.
    public let graphPath: [PackageIdentity]

    /// What the developer should do to resolve this.
    public let suggestedAction: String

    /// The package this finding is about.
    public let affectedPackage: PackageIdentity

    /// A string the developer can add to avie-suppress.json to silence this.
    public var suppressionKey: String {
        "\(ruleID.rawValue):\(affectedPackage.value)"
    }
}
```

### 5.5 Rule ID Enumeration

```swift
// Sources/AvieCore/Models/RuleID.swift

/// Stable, versioned identifiers for every rule Avie can enforce.
/// These identifiers appear in SARIF output, JSON output, and suppression files.
/// Once published, these values must NEVER change (they become part of
/// suppression file contracts and CI pipeline configurations).
public enum RuleID: String, Codable, Sendable, CaseIterable {

    // MARK: - v1 Rules (Graph-Provable, Proven Confidence)

    /// A package appears in Package.resolved but is unreachable from any
    /// root target via the product/dependency graph.
    case unreachablePin = "AVIE001"

    /// A package that is only a dependency of test targets is transitively
    /// reachable from a production target's dependency graph.
    case testLeakage = "AVIE002"

    /// A new direct dependency introduces more than N transitive packages.
    /// N is configurable. Default: 10.
    case excessiveFanout = "AVIE003"

    /// A pull request introduces a .binaryTarget dependency.
    case binaryTargetIntroduced = "AVIE004"

    // MARK: - v2 Rules (Source-Evidence, Heuristic Confidence) — not implemented in v1
    // Kept here as documentation of the planned rule namespace.

    // case declaredImportUnused = "AVIE101"    // SwiftIndexStore evidence
    // case sdkSubstitutionAvailable = "AVIE102" // Platform SDK analysis
    // case stalePackage = "AVIE201"             // Advisory, external metadata
}
```

### 5.6 Analysis Configuration

```swift
// Sources/AvieCore/Models/AvieConfiguration.swift

/// Project-level configuration for Avie.
/// Loaded from .avie.json in the project root if present.
/// All fields have sensible defaults so configuration is optional.
public struct AvieConfiguration: Codable, Sendable {

    /// Path to the Package.swift directory being analyzed.
    /// Defaults to the current working directory.
    public var packageDirectory: String = "."

    /// Rule-specific overrides.
    public var rules: RuleConfiguration = .init()

    public struct RuleConfiguration: Codable, Sendable {
        /// AVIE003: Maximum number of transitive dependencies a new direct
        /// dependency may introduce before a warning is emitted.
        public var fanoutThreshold: Int = 10

        /// Which rules are enabled. Default: all v1 rules.
        public var enabled: [RuleID] = [.unreachablePin, .testLeakage,
                                         .excessiveFanout, .binaryTargetIntroduced]

        /// Which rules cause a non-zero exit code (CI failure).
        /// By default only .error severity rules fail CI.
        public var failOn: [RuleID] = [.unreachablePin, .testLeakage,
                                        .binaryTargetIntroduced]
    }

    /// Packages to globally suppress from all findings.
    /// Use case: a known false positive for your specific project structure.
    public var suppressions: [String] = []

    public init() {}
}
```

### 5.7 Suppression File Model

```swift
// Sources/AvieCore/Models/Suppression.swift

/// Represents a single suppressed finding.
/// Stored in avie-suppress.json at the package root.
///
/// KEY DESIGN DECISION: Suppression keys are identity-based (ruleID:packageName),
/// NOT graph-state-based. This means suppression files remain stable even as
/// the dependency graph changes, preventing the Git merge conflict problem
/// that plagues graph-state-based baseline files.
public struct Suppression: Codable, Sendable {
    /// The suppression key in format "AVIE001:some-package-identity"
    public let key: String

    /// Why this finding was suppressed. Mandatory field.
    /// Forces developers to document intentional suppressions.
    public let reason: String

    /// Who added this suppression and when (ISO8601 date string).
    public let addedBy: String
    public let addedAt: String
}

public struct SuppressionFile: Codable, Sendable {
    public var suppressions: [Suppression] = []

    public static let fileName = "avie-suppress.json"
}
```

---

## 6. Module 2: AvieResolver — Graph Ingestion

**Location:** `Sources/AvieResolver/`  
**External Dependencies:** AvieCore only  
**Purpose:** All interaction with the external world (file system, process execution) is isolated here. No other module touches the file system or launches processes. This makes everything else unit-testable with mock data.

### 6.1 The SPM Resolver Wrapper

```swift
// Sources/AvieResolver/SPMResolver.swift

import Foundation
import AvieCore

/// Executes `swift package show-dependencies --format json` and parses the output
/// into Avie's domain model.
///
/// CRITICAL OPERATIONAL REQUIREMENTS (from architecture review):
/// 1. Must be invoked from the directory containing Package.swift
/// 2. Must handle the case where packages are not yet resolved
/// 3. Must pass --disable-automatic-resolution in CI mode to prevent
///    unexpected network calls
/// 4. Must never be called for Xcode-managed projects (.xcodeproj) in v1
///
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

    /// Validates that the target directory is a resolvable SPM package.
    /// Throws descriptive errors before launching any processes.
    public func validate() throws {
        // Check directory exists
        guard FileManager.default.fileExists(atPath: packageDirectory.path) else {
            throw ResolverError.packageDirectoryNotFound(packageDirectory)
        }

        // Check for Xcode project (not supported in v1)
        let xcodeprojURLs = try FileManager.default.contentsOfDirectory(
            at: packageDirectory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "xcodeproj" }

        if !xcodeprojURLs.isEmpty {
            throw ResolverError.xcodeProjectDetected(xcodeprojURLs[0])
        }

        // Check Package.swift exists
        let manifestURL = packageDirectory.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ResolverError.packageManifestNotFound(packageDirectory)
        }
    }

    /// Executes `swift package show-dependencies --format json` and returns
    /// the raw parsed dependency tree.
    public func resolve() throws -> SPMDependencyOutput {
        var arguments = ["package", "show-dependencies", "--format", "json"]

        // In CI mode, prevent unexpected network resolution attempts.
        // This keeps CI runs deterministic and fast.
        if isCI {
            arguments.append("--disable-automatic-resolution")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
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
            // Detect the "not resolved" case specifically
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
```

### 6.2 SPM JSON Output Model

```swift
// Sources/AvieResolver/SPMDependencyOutput.swift

import AvieCore

/// Codable models that exactly match the JSON schema of
/// `swift package show-dependencies --format json`.
///
/// IMPORTANT: This schema is internal to AvieResolver.
/// The rest of Avie never sees this type — AvieResolver converts it
/// into AvieCore domain types before returning.

public struct SPMDependencyOutput: Codable {
    public let name: String
    public let url: String
    public let version: String
    public let path: String
    public let dependencies: [SPMDependencyOutput]

    // NOTE: The show-dependencies output is recursive — each dependency
    // lists its own dependencies. This is the source of graph edge data.
    // Package.resolved does NOT have this — this is why we use show-dependencies
    // and NOT Package.resolved as our primary data source.
}
```

### 6.3 Dependency Output → Domain Model Transformer

```swift
// Sources/AvieResolver/DependencyTransformer.swift

import AvieCore

/// Converts the recursive SPMDependencyOutput tree into a flat dictionary
/// of ResolvedPackage domain objects with explicit edges.
///
/// This is the critical transformation step. The output of this transformer
/// is what the AvieGraph module consumes.
public struct DependencyTransformer {

    public init() {}

    public func transform(_ root: SPMDependencyOutput) -> [PackageIdentity: ResolvedPackage] {
        var packages: [PackageIdentity: ResolvedPackage] = [:]
        transformRecursive(root, isRoot: true, into: &packages)
        return packages
    }

    private func transformRecursive(
        _ node: SPMDependencyOutput,
        isRoot: Bool,
        into packages: inout [PackageIdentity: ResolvedPackage]
    ) {
        let identity = PackageIdentity(node.name)

        // Avoid processing the same package twice (diamond dependencies)
        guard packages[identity] == nil else { return }

        let directDepIDs = node.dependencies.map { PackageIdentity($0.name) }

        let resolved = ResolvedPackage(
            id: identity,
            url: node.url,
            version: node.version,
            name: node.name,
            directDependencies: directDepIDs,
            isRoot: isRoot,
            containsBinaryTarget: false // Binary target detection is in v1 rules
        )

        packages[identity] = resolved

        // Recurse into dependencies
        for dep in node.dependencies {
            transformRecursive(dep, isRoot: false, into: &packages)
        }
    }
}
```

### 6.4 Package.swift Manifest Reader

```swift
// Sources/AvieResolver/ManifestReader.swift

import Foundation
import AvieCore

/// Parses Package.swift to extract target-level declarations.
/// This is needed for the TestLeakage rule, which requires knowing
/// which targets are test targets and which packages they depend on.
///
/// IMPLEMENTATION NOTE: Parsing Package.swift properly requires either:
/// Option A: Execute `swift package dump-package` (returns JSON manifest)
/// Option B: Use SwiftSyntax to parse the Swift source
///
/// We use Option A (dump-package) for the same reason we use show-dependencies:
/// we leverage the SPM toolchain's own parser instead of reimplementing it.
/// This ensures correctness across Package.swift format variations.
public final class ManifestReader {

    private let packageDirectory: URL

    public init(packageDirectory: URL) {
        self.packageDirectory = packageDirectory
    }

    public struct ManifestData: Codable {
        public let name: String
        public let targets: [ManifestTarget]
        public let dependencies: [ManifestDependency]
    }

    public struct ManifestTarget: Codable {
        public let name: String
        public let type: String  // "regular", "executable", "test", "plugin", "macro"
        public let dependencies: [ManifestTargetDependency]
    }

    public struct ManifestTargetDependency: Codable {
        // dump-package represents target dependencies in a complex union type.
        // We extract package names from the "product" and "byName" variants.
        public let product: ProductDependency?
        public let byName: [String?]?  // [name, condition]

        public struct ProductDependency: Codable {
            public let name: String
            public let package: String
        }
    }

    public struct ManifestDependency: Codable {
        public let identity: String
        public let type: String
        public let url: String?
        public let path: String?
    }

    public func read() throws -> ManifestData {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["package", "dump-package"]
        process.currentDirectoryURL = packageDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            throw NSError(domain: "AvieResolver", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "dump-package failed: \(err)"])
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return try JSONDecoder().decode(ManifestData.self, from: data)
    }
}
```

---

## 7. Module 3: AvieGraph — Graph Engine

**Location:** `Sources/AvieGraph/`  
**External Dependencies:** AvieCore only  
**Purpose:** Accepts the flat dictionary of `ResolvedPackage` objects from AvieResolver and provides graph traversal, reachability queries, and topological analysis. This module is pure computation — no I/O.

### 7.1 The Dependency Graph

```swift
// Sources/AvieGraph/DependencyGraph.swift

import AvieCore

/// The central graph data structure.
/// Represents the entire resolved dependency graph as an adjacency list.
///
/// DESIGN DECISION: We use an adjacency list (dictionary of identity → [identity])
/// rather than a matrix because Swift package graphs are sparse.
/// A 100-package project has maybe 150 edges. A matrix would waste memory.
public final class DependencyGraph {

    /// All packages in the graph, keyed by identity.
    public let packages: [PackageIdentity: ResolvedPackage]

    /// Forward adjacency: package → its direct dependencies.
    public let adjacency: [PackageIdentity: [PackageIdentity]]

    /// Reverse adjacency: package → packages that depend on it.
    /// Used for "why is this package in the graph?" queries.
    public let reverseAdjacency: [PackageIdentity: [PackageIdentity]]

    /// The root package identity.
    public let rootIdentity: PackageIdentity

    public init(packages: [PackageIdentity: ResolvedPackage]) throws {
        guard let root = packages.values.first(where: { $0.isRoot }) else {
            throw GraphError.noRootPackageFound
        }

        self.packages = packages
        self.rootIdentity = root.id

        // Build adjacency list
        var adj: [PackageIdentity: [PackageIdentity]] = [:]
        var rev: [PackageIdentity: [PackageIdentity]] = [:]

        for package in packages.values {
            adj[package.id] = package.directDependencies
            for dep in package.directDependencies {
                rev[dep, default: []].append(package.id)
            }
        }

        self.adjacency = adj
        self.reverseAdjacency = rev
    }

    public enum GraphError: Error {
        case noRootPackageFound
    }
}
```

### 7.2 Graph Traversal Algorithms

```swift
// Sources/AvieGraph/GraphTraversal.swift

import AvieCore

/// Provides BFS and DFS traversal over a DependencyGraph.
/// These algorithms are the foundation of every rule in AvieRules.
public struct GraphTraversal {

    public let graph: DependencyGraph

    public init(graph: DependencyGraph) {
        self.graph = graph
    }

    // MARK: - Reachability

    /// Returns the set of all package identities reachable from the given
    /// starting node via BFS traversal.
    ///
    /// This is the core algorithm for AVIE001 (Unreachable Pin):
    /// A package is unreachable if it is NOT in the set returned by
    /// reachablePackages(from: rootIdentity)
    public func reachablePackages(from start: PackageIdentity) -> Set<PackageIdentity> {
        var visited = Set<PackageIdentity>()
        var queue = [start]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard !visited.contains(current) else { continue }
            visited.insert(current)

            let neighbors = graph.adjacency[current] ?? []
            queue.append(contentsOf: neighbors.filter { !visited.contains($0) })
        }

        return visited
    }

    /// Returns the shortest path from `start` to `target` using BFS.
    /// Returns nil if no path exists.
    ///
    /// Used to populate Finding.graphPath — every finding shows the exact
    /// path that proves the finding.
    public func shortestPath(
        from start: PackageIdentity,
        to target: PackageIdentity
    ) -> [PackageIdentity]? {
        if start == target { return [start] }

        var visited = Set<PackageIdentity>()
        var queue: [[PackageIdentity]] = [[start]]

        while !queue.isEmpty {
            let path = queue.removeFirst()
            let current = path.last!

            guard !visited.contains(current) else { continue }
            visited.insert(current)

            for neighbor in graph.adjacency[current] ?? [] {
                let newPath = path + [neighbor]
                if neighbor == target { return newPath }
                queue.append(newPath)
            }
        }

        return nil
    }

    // MARK: - Transitive Depth & Fan-out

    /// Returns all transitive dependencies of a given package (including direct).
    /// Used for AVIE003 (Excessive Fan-out).
    public func allTransitiveDependencies(
        of packageID: PackageIdentity
    ) -> Set<PackageIdentity> {
        var result = reachablePackages(from: packageID)
        result.remove(packageID)  // exclude self
        return result
    }

    /// Returns the maximum depth of the dependency tree rooted at the given package.
    public func maximumDepth(from start: PackageIdentity) -> Int {
        func dfs(_ node: PackageIdentity, _ visited: inout Set<PackageIdentity>) -> Int {
            if visited.contains(node) { return 0 }
            visited.insert(node)
            let childDepths = (graph.adjacency[node] ?? []).map { child -> Int in
                var v = visited
                return 1 + dfs(child, &v)
            }
            return childDepths.max() ?? 0
        }
        var visited = Set<PackageIdentity>()
        return dfs(start, &visited)
    }

    // MARK: - Topology

    /// Returns a topologically sorted list of all packages.
    /// Packages with no dependencies come first.
    /// Uses Kahn's algorithm.
    public func topologicalSort() -> [PackageIdentity] {
        var inDegree: [PackageIdentity: Int] = [:]
        for id in graph.packages.keys { inDegree[id] = 0 }

        for (_, deps) in graph.adjacency {
            for dep in deps {
                inDegree[dep, default: 0] += 1
            }
        }

        var queue = inDegree.filter { $0.value == 0 }.map { $0.key }.sorted { $0.value < $1.value }
        var result: [PackageIdentity] = []

        while !queue.isEmpty {
            let node = queue.removeFirst()
            result.append(node)
            for neighbor in graph.adjacency[node] ?? [] {
                inDegree[neighbor]! -= 1
                if inDegree[neighbor]! == 0 {
                    queue.append(neighbor)
                }
            }
        }

        return result
    }

    // MARK: - "Why is this here?" — Reverse Path

    /// Finds all paths from root to the given target package.
    /// Used to answer "why is X in my dependency graph?" queries.
    /// Exposed via `avie explain <package-name>` subcommand.
    public func allPaths(
        from start: PackageIdentity,
        to target: PackageIdentity,
        maxPaths: Int = 10
    ) -> [[PackageIdentity]] {
        var results: [[PackageIdentity]] = []
        var currentPath: [PackageIdentity] = [start]
        var visited = Set<PackageIdentity>()

        func dfs(_ node: PackageIdentity) {
            if results.count >= maxPaths { return }
            if node == target {
                results.append(currentPath)
                return
            }
            visited.insert(node)
            for neighbor in graph.adjacency[node] ?? [] {
                if !visited.contains(neighbor) {
                    currentPath.append(neighbor)
                    dfs(neighbor)
                    currentPath.removeLast()
                }
            }
            visited.remove(node)
        }

        dfs(start)
        return results
    }
}
```

---

## 8. Module 4: AvieRules — Analysis Passes

**Location:** `Sources/AvieRules/`  
**External Dependencies:** AvieCore, AvieGraph  
**Purpose:** Implements each rule as an isolated, independently testable analysis pass. Each rule takes a graph (and optionally manifest data) and returns an array of `Finding` objects.

### 8.1 Rule Protocol

```swift
// Sources/AvieRules/Rule.swift

import AvieCore
import AvieGraph

/// Protocol that every Avie rule must conform to.
/// Rules are stateless functions from (graph + context) → [Finding].
public protocol Rule {
    var id: RuleID { get }
    var severity: Finding.Severity { get }
    var name: String { get }
    var description: String { get }

    func analyze(
        graph: DependencyGraph,
        traversal: GraphTraversal,
        context: RuleContext
    ) throws -> [Finding]
}

/// Context passed to every rule containing configuration and manifest data.
public struct RuleContext {
    public let configuration: AvieConfiguration
    public let manifestData: ManifestReader.ManifestData?
    public let suppressions: Set<String>  // suppression keys to skip

    public init(
        configuration: AvieConfiguration,
        manifestData: ManifestReader.ManifestData?,
        suppressions: Set<String>
    ) {
        self.configuration = configuration
        self.manifestData = manifestData
        self.suppressions = suppressions
    }
}
```

### 8.2 Rule: AVIE001 — Unreachable Pin

```swift
// Sources/AvieRules/Rules/UnreachablePinRule.swift

import AvieCore
import AvieGraph

/// AVIE001: Unreachable Pin
///
/// WHAT IT DETECTS:
/// A package appears in the resolved graph but is not reachable from the
/// root package via any dependency path.
///
/// WHY THIS HAPPENS:
/// - A dependency was removed from Package.swift but `swift package resolve`
///   wasn't re-run (stale lockfile)
/// - A dependency was removed but others in the graph still transitively
///   require it (this is NOT a false positive — SPM should keep it)
///
/// FALSE POSITIVE RISK:
/// - Packages that are dependencies of OTHER dependencies (transitively required)
///   will appear reachable from root and will NOT be flagged. Correct.
/// - Stale lockfile pins (removed from manifest but not from resolved file)
///   WILL be flagged. These are legitimate findings — re-running resolve fixes them.
///
/// CONFIDENCE: proven — pure graph math
public struct UnreachablePinRule: Rule {
    public let id = RuleID.unreachablePin
    public let severity = Finding.Severity.error
    public let name = "Unreachable Pinned Package"
    public let description = """
        A package is pinned in the resolved dependency graph but is not \
        reachable from any root target. This typically indicates a stale \
        package reference that should be removed.
        """

    public init() {}

    public func analyze(
        graph: DependencyGraph,
        traversal: GraphTraversal,
        context: RuleContext
    ) throws -> [Finding] {
        let reachable = traversal.reachablePackages(from: graph.rootIdentity)

        return graph.packages.values
            .filter { !$0.isRoot && !reachable.contains($0.id) }
            .filter { !context.suppressions.contains("\(id.rawValue):\($0.id.value)") }
            .map { unreachablePackage in
                Finding(
                    id: UUID(),
                    ruleID: id,
                    severity: severity,
                    confidence: .proven,
                    summary: "\(unreachablePackage.name) is pinned but unreachable from root",
                    detail: """
                        '\(unreachablePackage.name)' (\(unreachablePackage.version)) \
                        appears in the resolved dependency graph but no path exists \
                        from the root package to this dependency. \
                        This may be a stale lockfile entry. \
                        Run `swift package resolve` to clean up the lockfile.
                        """,
                    graphPath: [],  // Empty path = the point is there IS no path
                    suggestedAction: "Run `swift package resolve` to remove stale pins, or check if this package was intentionally removed from Package.swift.",
                    affectedPackage: unreachablePackage.id
                )
            }
    }
}
```

### 8.3 Rule: AVIE002 — Test Leakage

```swift
// Sources/AvieRules/Rules/TestLeakageRule.swift

import AvieCore
import AvieGraph

/// AVIE002: Test Leakage
///
/// WHAT IT DETECTS:
/// A package that is a dependency of a test target is transitively reachable
/// from a production target's dependency graph.
///
/// WHY THIS MATTERS:
/// Test frameworks (Quick, Nimble, etc.) should never be compiled into
/// production binary artifacts. If they're reachable from production targets,
/// they risk being included in App Store builds.
///
/// IMPLEMENTATION NOTE:
/// This rule requires manifest data (from `swift package dump-package`) to
/// determine which targets are test targets. Without manifest data, this rule
/// is skipped and a note is emitted explaining why.
///
/// CONFIDENCE: proven (with manifest data), skipped (without)
public struct TestLeakageRule: Rule {
    public let id = RuleID.testLeakage
    public let severity = Finding.Severity.error
    public let name = "Test Dependency Leaking Into Production Target"
    public let description = """
        A package declared as a test dependency is transitively reachable \
        from a production target. Test frameworks must never be included in \
        production builds.
        """

    public init() {}

    public func analyze(
        graph: DependencyGraph,
        traversal: GraphTraversal,
        context: RuleContext
    ) throws -> [Finding] {
        guard let manifest = context.manifestData else {
            // Cannot run this rule without manifest data.
            // AvieRuleEngine will emit a note about this.
            return []
        }

        // Identify packages that are exclusively depended on by test targets
        let testOnlyPackages = identifyTestOnlyPackages(manifest: manifest, graph: graph)

        // Find production target dependencies
        let productionPackages = identifyProductionReachablePackages(
            manifest: manifest,
            traversal: traversal
        )

        // A test-leakage occurs when a test-only package is reachable
        // from a production target
        let leaking = testOnlyPackages.intersection(productionPackages)

        return leaking
            .filter { !context.suppressions.contains("\(id.rawValue):\($0.value)") }
            .compactMap { leakingPackageID -> Finding? in
                guard let pkg = graph.packages[leakingPackageID] else { return nil }

                // Find the path from root that reaches this test-only package
                // via a production target
                let path = traversal.shortestPath(
                    from: graph.rootIdentity,
                    to: leakingPackageID
                ) ?? []

                return Finding(
                    id: UUID(),
                    ruleID: id,
                    severity: severity,
                    confidence: .proven,
                    summary: "\(pkg.name) is a test-only dependency reachable from production targets",
                    detail: """
                        '\(pkg.name)' is declared as a dependency of a test target but \
                        is also reachable from at least one production target. \
                        Test frameworks and test-only utilities should not be reachable \
                        from production code as they risk inclusion in App Store binaries.
                        """,
                    graphPath: path,
                    suggestedAction: """
                        Review the dependency declarations for '\(pkg.name)'. \
                        Ensure it is only listed as a dependency in .testTarget() declarations. \
                        Remove it from any .target() or .executableTarget() dependency lists.
                        """,
                    affectedPackage: leakingPackageID
                )
            }
    }

    private func identifyTestOnlyPackages(
        manifest: ManifestReader.ManifestData,
        graph: DependencyGraph
    ) -> Set<PackageIdentity> {
        var testPackages = Set<PackageIdentity>()
        var productionPackages = Set<PackageIdentity>()

        for target in manifest.targets {
            let packageDeps = extractPackageDependencies(from: target)
            if target.type == "test" {
                packageDeps.forEach { testPackages.insert(PackageIdentity($0)) }
            } else if target.type != "plugin" {
                packageDeps.forEach { productionPackages.insert(PackageIdentity($0)) }
            }
        }

        return testPackages.subtracting(productionPackages)
    }

    private func identifyProductionReachablePackages(
        manifest: ManifestReader.ManifestData,
        traversal: GraphTraversal
    ) -> Set<PackageIdentity> {
        let productionTargetDeps: Set<PackageIdentity> = manifest.targets
            .filter { $0.type != "test" && $0.type != "plugin" }
            .flatMap { extractPackageDependencies(from: $0) }
            .reduce(into: Set<PackageIdentity>()) { $0.insert(PackageIdentity($1)) }

        var reachable = Set<PackageIdentity>()
        for depID in productionTargetDeps {
            reachable.formUnion(traversal.reachablePackages(from: depID))
        }
        return reachable
    }

    private func extractPackageDependencies(
        from target: ManifestReader.ManifestTarget
    ) -> [String] {
        target.dependencies.compactMap { dep -> String? in
            if let product = dep.product {
                return product.package
            }
            return dep.byName?.first ?? nil
        }
    }
}
```

### 8.4 Rule: AVIE003 — Excessive Fan-out

```swift
// Sources/AvieRules/Rules/ExcessiveFanoutRule.swift

import AvieCore
import AvieGraph

/// AVIE003: Excessive Fan-out
///
/// WHAT IT DETECTS:
/// A direct dependency of the root package pulls in more than N transitive
/// dependencies (configurable via .avie.json, default: 10).
///
/// DESIGN DECISION (from architecture review):
/// The threshold MUST be configurable, not hardcoded. Projects have legitimately
/// different standards. A CLI tool might tolerate 3 transitive deps max.
/// A full app might tolerate 25. Hardcoding this would make the rule
/// wrong for half the user base.
///
/// WHERE THIS IS MOST USEFUL: PR Diff mode. Flagging when a NEW dependency
/// introduces excessive fan-out in a pull request is more actionable than
/// flagging existing dependencies.
///
/// CONFIDENCE: proven — pure arithmetic on graph
public struct ExcessiveFanoutRule: Rule {
    public let id = RuleID.excessiveFanout
    public let severity = Finding.Severity.warning  // warning, not error
    public let name = "Excessive Transitive Fan-out"
    public let description = """
        A direct dependency introduces more transitive dependencies than the \
        configured threshold. Review whether this dependency is appropriate \
        for the scope of its use.
        """

    public init() {}

    public func analyze(
        graph: DependencyGraph,
        traversal: GraphTraversal,
        context: RuleContext
    ) throws -> [Finding] {
        let threshold = context.configuration.rules.fanoutThreshold
        let rootDirectDeps = graph.adjacency[graph.rootIdentity] ?? []

        return rootDirectDeps.compactMap { depID -> Finding? in
            guard let pkg = graph.packages[depID] else { return nil }
            guard !context.suppressions.contains("\(id.rawValue):\(depID.value)") else {
                return nil
            }

            let transitiveDeps = traversal.allTransitiveDependencies(of: depID)
            guard transitiveDeps.count > threshold else { return nil }

            return Finding(
                id: UUID(),
                ruleID: id,
                severity: severity,
                confidence: .proven,
                summary: "\(pkg.name) introduces \(transitiveDeps.count) transitive dependencies (threshold: \(threshold))",
                detail: """
                    '\(pkg.name)' is a direct dependency that transitively pulls in \
                    \(transitiveDeps.count) additional packages. \
                    This may indicate the dependency is heavier than expected for \
                    its intended use case. Consider whether a lighter-weight \
                    alternative exists or whether all \(transitiveDeps.count) \
                    packages are genuinely needed.

                    Transitive packages: \(transitiveDeps.map(\.value).sorted().joined(separator: ", "))
                    """,
                graphPath: [graph.rootIdentity, depID],
                suggestedAction: """
                    Review whether '\(pkg.name)' is being used for a narrow purpose \
                    that could be served by a lighter-weight package. \
                    Alternatively, increase the fanout threshold in .avie.json if \
                    this level of transitive dependencies is acceptable for your project.
                    """,
                affectedPackage: depID
            )
        }
    }
}
```

### 8.5 Rule: AVIE004 — Binary Target Introduced

```swift
// Sources/AvieRules/Rules/BinaryTargetRule.swift

import AvieCore
import AvieGraph

/// AVIE004: Binary Target Introduced
///
/// WHAT IT DETECTS:
/// A dependency in the graph contains a .binaryTarget (XCFramework).
///
/// WHY THIS MATTERS:
/// Binary targets (XCFrameworks) cannot be statically analyzed for:
/// - Security vulnerabilities (no source to audit)
/// - Code size contribution (only measurable after linking)
/// - License compliance (no source to review)
///
/// In CI Diff Mode, this rule fires specifically when a NEW binary target
/// is introduced in a PR. In local audit mode, it flags all binary targets.
///
/// IMPLEMENTATION NOTE:
/// Detecting binary targets requires checking package manifests, not just
/// the dependency graph edges. The containsBinaryTarget field on ResolvedPackage
/// is populated by examining the show-dependencies output combined with
/// dump-package for each dependency (expensive). For v1, we use a simpler
/// heuristic: if a package's URL ends in .zip or the dependency type is
/// "binary" in dump-package output, flag it.
///
/// CONFIDENCE: proven
public struct BinaryTargetRule: Rule {
    public let id = RuleID.binaryTargetIntroduced
    public let severity = Finding.Severity.error
    public let name = "Binary Target Dependency"
    public let description = """
        A dependency contains a binary target (XCFramework) that cannot be \
        statically analyzed for security or code size contribution.
        """

    public init() {}

    public func analyze(
        graph: DependencyGraph,
        traversal: GraphTraversal,
        context: RuleContext
    ) throws -> [Finding] {
        return graph.packages.values
            .filter { $0.containsBinaryTarget && !$0.isRoot }
            .filter { !context.suppressions.contains("\(id.rawValue):\($0.id.value)") }
            .map { pkg in
                let path = traversal.shortestPath(
                    from: graph.rootIdentity,
                    to: pkg.id
                ) ?? []

                return Finding(
                    id: UUID(),
                    ruleID: id,
                    severity: severity,
                    confidence: .proven,
                    summary: "\(pkg.name) contains a binary target (XCFramework)",
                    detail: """
                        '\(pkg.name)' contains a .binaryTarget declaration, meaning \
                        it distributes a pre-compiled XCFramework. Binary targets \
                        cannot be audited for security vulnerabilities, their code size \
                        contribution cannot be estimated without full compilation, and \
                        their licenses cannot be reviewed from source. \
                        This is particularly important for packages introduced in PRs.
                        """,
                    graphPath: path,
                    suggestedAction: """
                        Review '\(pkg.name)' and verify:
                        1. The XCFramework comes from a trusted, audited source
                        2. The license is compatible with your project
                        3. No open-source alternative with full source is available
                        If this binary target is intentional and reviewed, add a suppression.
                        """,
                    affectedPackage: pkg.id
                )
            }
    }
}
```

### 8.6 Rule Engine

```swift
// Sources/AvieRules/RuleEngine.swift

import AvieCore
import AvieGraph

/// Orchestrates the execution of all enabled rules.
/// Returns a structured AnalysisResult containing all findings.
public final class RuleEngine {

    private let rules: [any Rule]
    private let context: RuleContext

    public init(configuration: AvieConfiguration,
                manifestData: ManifestReader.ManifestData?,
                suppressions: SuppressionFile) {
        self.context = RuleContext(
            configuration: configuration,
            manifestData: manifestData,
            suppressions: Set(suppressions.suppressions.map(\.key))
        )

        // Instantiate only enabled rules
        let enabledRuleIDs = Set(configuration.rules.enabled)
        var allRules: [any Rule] = [
            UnreachablePinRule(),
            TestLeakageRule(),
            ExcessiveFanoutRule(),
            BinaryTargetRule(),
        ]
        self.rules = allRules.filter { enabledRuleIDs.contains($0.id) }
    }

    public struct AnalysisResult {
        public let findings: [Finding]
        public let graph: DependencyGraph
        public let executedRules: [RuleID]
        public let skippedRules: [(RuleID, reason: String)]
        public let metadata: Metadata

        public struct Metadata {
            public let packageDirectory: String
            public let totalPackages: Int
            public let directDependencies: Int
            public let transitiveDepth: Int
            public let analysisDate: Date
        }
    }

    public func run(graph: DependencyGraph, traversal: GraphTraversal) throws -> AnalysisResult {
        var allFindings: [Finding] = []
        var executed: [RuleID] = []
        var skipped: [(RuleID, reason: String)] = []

        for rule in rules {
            // Special case: TestLeakageRule requires manifest data
            if rule.id == .testLeakage && context.manifestData == nil {
                skipped.append((.testLeakage, reason: "Manifest data unavailable (dump-package failed)"))
                continue
            }

            do {
                let findings = try rule.analyze(
                    graph: graph,
                    traversal: traversal,
                    context: context
                )
                allFindings.append(contentsOf: findings)
                executed.append(rule.id)
            } catch {
                skipped.append((rule.id, reason: "Rule execution failed: \(error.localizedDescription)"))
            }
        }

        let depth = traversal.maximumDepth(from: graph.rootIdentity)
        let directDeps = (graph.adjacency[graph.rootIdentity] ?? []).count

        return AnalysisResult(
            findings: allFindings,
            graph: graph,
            executedRules: executed,
            skippedRules: skipped,
            metadata: AnalysisResult.Metadata(
                packageDirectory: ".",
                totalPackages: graph.packages.count,
                directDependencies: directDeps,
                transitiveDepth: depth,
                analysisDate: Date()
            )
        )
    }
}
```

---

## 9. Module 5: AvieDiff — PR Diff Engine

**Location:** `Sources/AvieDiff/`  
**External Dependencies:** AvieCore, AvieGraph, AvieRules  
**Purpose:** Implements the PR Diff Mode — the flagship feature of Avie. Accepts two graph snapshots (base branch, head branch) and computes what changed.

### 9.1 Graph Snapshot

```swift
// Sources/AvieDiff/GraphSnapshot.swift

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
}
```

### 9.2 Diff Engine

```swift
// Sources/AvieDiff/DiffEngine.swift

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
```

---

## 10. Module 6: AvieOutput — Formatters

**Location:** `Sources/AvieOutput/`  
**External Dependencies:** AvieCore, AvieRules, AvieDiff  
**Purpose:** All output formatting is isolated here. The CLI layer never constructs output strings. This module is independently testable by checking output strings against expected values.

### 10.1 Output Protocol

```swift
// Sources/AvieOutput/OutputFormatter.swift

import AvieCore
import AvieRules
import AvieDiff

public protocol OutputFormatter {
    /// Format a full audit result
    func format(result: RuleEngine.AnalysisResult) throws -> String

    /// Format a diff result
    func format(diff: DiffEngine.DiffResult) throws -> String
}
```

### 10.2 Terminal Formatter

```swift
// Sources/AvieOutput/Formatters/TerminalFormatter.swift

import AvieCore
import AvieRules
import AvieDiff

/// Produces human-readable, color-coded terminal output.
/// Uses ANSI escape codes. Color is disabled when output is not a TTY
/// (piped to file or another process) or when --no-color is passed.
public struct TerminalFormatter: OutputFormatter {

    private let useColor: Bool

    public init(useColor: Bool = true) {
        // Auto-detect TTY if not specified
        self.useColor = useColor && isatty(STDOUT_FILENO) != 0
    }

    // ANSI codes
    private var red: String    { useColor ? "\u{001B}[31m" : "" }
    private var yellow: String { useColor ? "\u{001B}[33m" : "" }
    private var green: String  { useColor ? "\u{001B}[32m" : "" }
    private var cyan: String   { useColor ? "\u{001B}[36m" : "" }
    private var bold: String   { useColor ? "\u{001B}[1m" : "" }
    private var reset: String  { useColor ? "\u{001B}[0m" : "" }
    private var dim: String    { useColor ? "\u{001B}[2m" : "" }

    public func format(result: RuleEngine.AnalysisResult) throws -> String {
        var lines: [String] = []

        // Header
        lines.append("\(bold)Avie Dependency Graph Audit\(reset)")
        lines.append("\(dim)─────────────────────────────\(reset)")
        lines.append("\(dim)Packages: \(result.metadata.totalPackages) total, \(result.metadata.directDependencies) direct\(reset)")
        lines.append("\(dim)Max depth: \(result.metadata.transitiveDepth)\(reset)")
        lines.append("")

        if result.findings.isEmpty {
            lines.append("\(green)✓ No findings. Graph looks clean.\(reset)")
        } else {
            // Group findings by severity
            let errors = result.findings.filter { $0.severity == .error }
            let warnings = result.findings.filter { $0.severity == .warning }

            for finding in errors {
                lines.append(formatFinding(finding, prefix: "\(red)error\(reset)"))
            }
            for finding in warnings {
                lines.append(formatFinding(finding, prefix: "\(yellow)warning\(reset)"))
            }

            lines.append("")
            lines.append("\(bold)Summary:\(reset) \(errors.count) error(s), \(warnings.count) warning(s)")
        }

        if !result.skippedRules.isEmpty {
            lines.append("")
            lines.append("\(dim)Skipped rules:\(reset)")
            for (ruleID, reason) in result.skippedRules {
                lines.append("  \(dim)\(ruleID.rawValue): \(reason)\(reset)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public func format(diff: DiffEngine.DiffResult) throws -> String {
        var lines: [String] = []

        lines.append("\(bold)Avie PR Diff Report\(reset)")
        lines.append("\(dim)────────────────────\(reset)")
        lines.append("")

        // Summary line
        let changeSymbol = diff.packageCountDelta > 0 ? "+" : (diff.packageCountDelta < 0 ? "-" : "=")
        lines.append("Package count: \(changeSymbol)\(abs(diff.packageCountDelta))  |  Depth delta: \(diff.depthDelta > 0 ? "+" : "")\(diff.depthDelta)")
        lines.append("")

        // New binary targets — always show prominently
        if !diff.newBinaryTargets.isEmpty {
            lines.append("\(red)\(bold)⚠ Binary targets introduced:\(reset)")
            for pkg in diff.newBinaryTargets {
                lines.append("  \(red)+ \(pkg.name) (\(pkg.version)) — XCFramework, cannot be source-audited\(reset)")
            }
            lines.append("")
        }

        // New direct dependencies with fan-out
        if !diff.newDirectDependencies.isEmpty {
            lines.append("\(bold)New direct dependencies:\(reset)")
            for pkg in diff.newDirectDependencies {
                let transitive = diff.transitiveFanoutByNewDep[pkg.id] ?? 0
                let transitiveWarning = transitive > 10 ? " \(yellow)(+\(transitive) transitive)\(reset)" : " \(dim)(+\(transitive) transitive)\(reset)"
                lines.append("  \(green)+ \(pkg.name) \(pkg.version)\(reset)\(transitiveWarning)")
            }
            lines.append("")
        }

        // New findings
        if !diff.newFindings.isEmpty {
            lines.append("\(red)\(bold)New violations introduced:\(reset)")
            for finding in diff.newFindings {
                lines.append(formatFinding(finding, prefix: "\(red)error\(reset)"))
            }
            lines.append("")
        }

        // Resolved findings
        if !diff.resolvedFindings.isEmpty {
            lines.append("\(green)Resolved violations:\(reset)")
            for finding in diff.resolvedFindings {
                lines.append("  \(green)✓ \(finding.summary)\(reset)")
            }
            lines.append("")
        }

        if diff.hasBlockingIssues {
            lines.append("\(red)\(bold)✗ This PR introduces blocking dependency issues.\(reset)")
        } else {
            lines.append("\(green)✓ No blocking issues introduced.\(reset)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatFinding(_ finding: Finding, prefix: String) -> String {
        var lines: [String] = []
        lines.append("  [\(prefix)] [\(dim)\(finding.ruleID.rawValue)\(reset)] \(finding.summary)")
        lines.append("  \(dim)\(finding.detail.prefix(200))\(reset)")

        if !finding.graphPath.isEmpty {
            let pathString = finding.graphPath.map(\.value).joined(separator: " → ")
            lines.append("  \(dim)Path: \(pathString)\(reset)")
        }

        lines.append("  \(cyan)→ \(finding.suggestedAction)\(reset)")
        lines.append("  \(dim)Suppress: avie suppress \(finding.suppressionKey)\(reset)")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
```

### 10.3 JSON Formatter

```swift
// Sources/AvieOutput/Formatters/JSONFormatter.swift

import Foundation
import AvieCore
import AvieRules
import AvieDiff

/// Produces machine-readable JSON output for CI consumption.
/// The JSON schema is stable and versioned.
public struct JSONFormatter: OutputFormatter {

    private let encoder: JSONEncoder

    public init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    public struct AuditReport: Codable {
        public let schemaVersion: String  // "1.0"
        public let metadata: RuleEngine.AnalysisResult.Metadata
        public let findings: [Finding]
        public let summary: Summary

        public struct Summary: Codable {
            public let totalPackages: Int
            public let errors: Int
            public let warnings: Int
            public let passed: Bool  // true if no error-severity findings
        }
    }

    public func format(result: RuleEngine.AnalysisResult) throws -> String {
        let errors = result.findings.filter { $0.severity == .error }.count
        let warnings = result.findings.filter { $0.severity == .warning }.count

        let report = AuditReport(
            schemaVersion: "1.0",
            metadata: result.metadata,
            findings: result.findings,
            summary: AuditReport.Summary(
                totalPackages: result.metadata.totalPackages,
                errors: errors,
                warnings: warnings,
                passed: errors == 0
            )
        )

        let data = try encoder.encode(report)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public func format(diff: DiffEngine.DiffResult) throws -> String {
        // DiffResult Codable conformance for JSON output
        // Implement similar structure
        return "{}" // TODO: DiffResult Codable implementation
    }
}
```

### 10.4 SARIF Formatter

```swift
// Sources/AvieOutput/Formatters/SARIFFormatter.swift

import Foundation
import AvieCore
import AvieRules
import AvieDiff

/// Produces SARIF 2.1.0 output for GitHub Code Scanning integration.
///
/// SARIF (Static Analysis Results Interchange Format) is the standard
/// consumed by GitHub Actions, GitLab SAST, and Azure DevOps.
///
/// When SARIF output is uploaded to GitHub, findings appear as:
/// - Inline annotations on the changed lines of a PR
/// - Entries in the "Security" tab of the repository
/// - Status checks on the PR
///
/// This is why SARIF is non-negotiable for real CI integration.
/// Terminal output alone is "hobbyware" (as noted in architecture review).
public struct SARIFFormatter: OutputFormatter {

    // SARIF 2.1.0 schema URL — required by GitHub
    private let schemaURL = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"

    public init() {}

    public func format(result: RuleEngine.AnalysisResult) throws -> String {
        let sarif = buildSARIF(findings: result.findings)
        let data = try JSONEncoder().encode(sarif)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func format(diff: DiffEngine.DiffResult) throws -> String {
        let sarif = buildSARIF(findings: diff.newFindings)
        let data = try JSONEncoder().encode(sarif)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - SARIF Structure

    private struct SARIF: Codable {
        let version: String
        let schema: String
        let runs: [Run]

        enum CodingKeys: String, CodingKey {
            case version
            case schema = "$schema"
            case runs
        }
    }

    private struct Run: Codable {
        let tool: Tool
        let results: [Result]
    }

    private struct Tool: Codable {
        let driver: Driver
    }

    private struct Driver: Codable {
        let name: String
        let version: String
        let informationUri: String
        let rules: [SARIFRule]
    }

    private struct SARIFRule: Codable {
        let id: String
        let name: String
        let shortDescription: Message
        let fullDescription: Message
        let defaultConfiguration: Configuration

        struct Configuration: Codable {
            let level: String  // "error", "warning", "note"
        }
    }

    private struct Result: Codable {
        let ruleId: String
        let level: String
        let message: Message
        let locations: [Location]
    }

    private struct Message: Codable {
        let text: String
    }

    private struct Location: Codable {
        let physicalLocation: PhysicalLocation
    }

    private struct PhysicalLocation: Codable {
        let artifactLocation: ArtifactLocation
        let region: Region
    }

    private struct ArtifactLocation: Codable {
        let uri: String
    }

    private struct Region: Codable {
        let startLine: Int
    }

    private func buildSARIF(findings: [Finding]) -> SARIF {
        let sarifRules = RuleID.allCases.map { ruleID -> SARIFRule in
            SARIFRule(
                id: ruleID.rawValue,
                name: ruleID.rawValue,
                shortDescription: Message(text: ruleID.rawValue),
                fullDescription: Message(text: ruleID.rawValue),
                defaultConfiguration: SARIFRule.Configuration(level: "error")
            )
        }

        let results = findings.map { finding -> Result in
            Result(
                ruleId: finding.ruleID.rawValue,
                level: finding.severity == .error ? "error" : "warning",
                message: Message(text: finding.summary + " " + finding.detail),
                locations: [
                    Location(physicalLocation: PhysicalLocation(
                        artifactLocation: ArtifactLocation(uri: "Package.swift"),
                        region: Region(startLine: 1)
                    ))
                ]
            )
        }

        return SARIF(
            version: "2.1.0",
            schema: schemaURL,
            runs: [
                Run(
                    tool: Tool(driver: Driver(
                        name: "avie",
                        version: "1.0.0",
                        informationUri: "https://github.com/yourusername/avie",
                        rules: sarifRules
                    )),
                    results: results
                )
            ]
        )
    }
}
```

---

## 11. Module 7: AvieCLI — Entry Point

**Location:** `Sources/AvieCLI/`  
**External Dependencies:** All modules + swift-argument-parser  
**Purpose:** Parses CLI arguments and orchestrates the pipeline.

### 11.1 Command Structure

```swift
// Sources/AvieCLI/AvieCommand.swift

import ArgumentParser

@main
struct Avie: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "avie",
        abstract: "Swift package graph diagnostics tool.",
        version: "1.0.0",
        subcommands: [
            AuditCommand.self,
            DiffCommand.self,
            SnapshotCommand.self,
            ExplainCommand.self,
            SuppressCommand.self,
        ],
        defaultSubcommand: AuditCommand.self
    )
}
```

### 11.2 Audit Command

```swift
// Sources/AvieCLI/Commands/AuditCommand.swift

import ArgumentParser
import Foundation
import AvieCore
import AvieResolver
import AvieGraph
import AvieRules
import AvieOutput

struct AuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Run a full dependency graph audit."
    )

    @Option(name: .shortAndLong, help: "Path to package directory")
    var path: String = "."

    @Option(name: .long, help: "Output format: terminal, json, sarif")
    var format: String = "terminal"

    @Flag(name: .long, help: "Disable color output")
    var noColor: Bool = false

    @Flag(name: .long, help: "CI mode: disable network resolution")
    var ci: Bool = false

    @Flag(name: .long, help: "Exit 0 even if findings are present")
    var noFail: Bool = false

    mutating func run() throws {
        let packageURL = URL(fileURLWithPath: path).standardized

        // Step 1: Validate the target directory
        let resolver = SPMResolver(packageDirectory: packageURL, isCI: ci)
        try resolver.validate()

        // Step 2: Resolve the dependency graph
        let spmOutput = try resolver.resolve()
        let packages = DependencyTransformer().transform(spmOutput)

        // Step 3: Optionally read manifest for richer analysis
        let manifestReader = ManifestReader(packageDirectory: packageURL)
        let manifestData = try? manifestReader.read()

        // Step 4: Build the graph
        let graph = try DependencyGraph(packages: packages)
        let traversal = GraphTraversal(graph: graph)

        // Step 5: Load configuration and suppressions
        let config = loadConfiguration(from: packageURL)
        let suppressions = loadSuppressions(from: packageURL)

        // Step 6: Run rules
        let engine = RuleEngine(
            configuration: config,
            manifestData: manifestData,
            suppressions: suppressions
        )
        let result = try engine.run(graph: graph, traversal: traversal)

        // Step 7: Format output
        let outputString: String
        switch format {
        case "json":
            outputString = try JSONFormatter().format(result: result)
        case "sarif":
            outputString = try SARIFFormatter().format(result: result)
        default:
            outputString = try TerminalFormatter(useColor: !noColor).format(result: result)
        }

        print(outputString)

        // Step 8: Exit with appropriate code
        let hasErrors = result.findings.contains { $0.severity == .error }
        if hasErrors && !noFail {
            throw ExitCode.failure
        }
    }

    private func loadConfiguration(from url: URL) -> AvieConfiguration {
        let configURL = url.appendingPathComponent(".avie.json")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AvieConfiguration.self, from: data)
        else { return AvieConfiguration() }
        return config
    }

    private func loadSuppressions(from url: URL) -> SuppressionFile {
        let suppressURL = url.appendingPathComponent(SuppressionFile.fileName)
        guard let data = try? Data(contentsOf: suppressURL),
              let file = try? JSONDecoder().decode(SuppressionFile.self, from: data)
        else { return SuppressionFile() }
        return file
    }
}
```

### 11.3 Snapshot Command

```swift
// Sources/AvieCLI/Commands/SnapshotCommand.swift
// Used in CI to capture a graph state for later diffing.

struct SnapshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Capture the current dependency graph as a JSON snapshot for PR diff comparison."
    )

    @Option(name: .shortAndLong, help: "Path to package directory")
    var path: String = "."

    @Option(name: .shortAndLong, help: "Output file path for the snapshot JSON")
    var output: String = "avie-snapshot.json"

    @Option(name: .long, help: "Git ref label for this snapshot (e.g. branch name)")
    var gitRef: String?

    mutating func run() throws {
        // Resolve, audit, and serialize to GraphSnapshot
        // ... (follows same pattern as AuditCommand, then serializes to JSON)
    }
}
```

### 11.4 Diff Command

```swift
// Sources/AvieCLI/Commands/DiffCommand.swift

struct DiffCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Compare two dependency graph snapshots (for PR analysis)."
    )

    @Option(name: .long, help: "Base branch snapshot JSON")
    var base: String

    @Option(name: .long, help: "Head (PR) branch snapshot JSON")
    var head: String

    @Option(name: .long, help: "Output format: terminal, json, sarif")
    var format: String = "terminal"

    mutating func run() throws {
        // Load both snapshots, run DiffEngine, format output
        // Exit non-zero if hasBlockingIssues
    }
}
```

### 11.5 Explain Command

```swift
// Sources/AvieCLI/Commands/ExplainCommand.swift

/// `avie explain <package-name>`
/// Answers: "Why is this package in my dependency graph?"
/// Shows all paths from root to the named package.
struct ExplainCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explain",
        abstract: "Explain why a package is in the dependency graph."
    )

    @Argument(help: "The package identity to explain (e.g. swift-argument-parser)")
    var packageName: String

    @Option(name: .shortAndLong, help: "Path to package directory")
    var path: String = "."

    mutating func run() throws {
        // Resolve graph, find all paths from root to packageName
        // Print all paths with explanations
    }
}
```

### 11.6 Suppress Command

```swift
// Sources/AvieCLI/Commands/SuppressCommand.swift

/// `avie suppress AVIE001:some-package --reason "This is intentional because..."`
/// Adds an entry to avie-suppress.json
struct SuppressCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "suppress",
        abstract: "Add a suppression for a specific finding."
    )

    @Argument(help: "Suppression key (e.g. AVIE001:swift-argument-parser)")
    var key: String

    @Option(name: .shortAndLong, help: "Reason for suppression (mandatory)")
    var reason: String

    mutating func run() throws {
        // Append to avie-suppress.json with current user and date
    }
}
```

---

## 12. Module 8: AviePlugin — SPM Command Plugin

**Location:** `Plugins/AviePlugin/`  
**Type:** SPM Command Plugin (NOT Build Tool Plugin — see decision log)

```swift
// Plugins/AviePlugin/AviePlugin.swift

import PackagePlugin
import Foundation

@main
struct AviePlugin: CommandPlugin {

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // Locate the avie executable
        let avieTool = try context.tool(named: "avie")

        // Default to audit command
        var processArgs = ["audit", "--path", context.package.directory.string]

        // Pass through any user-provided arguments
        var argExtractor = ArgumentExtractor(arguments)
        if let format = argExtractor.extractOption(named: "format").first {
            processArgs += ["--format", format]
        }
        if argExtractor.extractFlag(named: "ci") > 0 {
            processArgs.append("--ci")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: avieTool.path.string)
        process.arguments = processArgs

        try process.run()
        process.waitUntilExit()

        // Propagate exit code so `swift package avie-audit` fails in CI
        // when findings are present
        if process.terminationStatus != 0 {
            throw ExitCode(process.terminationStatus)
        }
    }
}
```

---

## 13. Cross-Cutting Concerns

### 13.1 Error Handling Philosophy

Every error Avie can emit must be:
1. **Actionable** — tell the developer exactly what to do
2. **Context-aware** — include the file path, package name, or command that failed
3. **Never silent** — stderr for errors, stdout for findings

Use `LocalizedError` everywhere. Never use `fatalError()` in production paths. Reserve `precondition()` only for invariants that represent programming errors.

### 13.2 Configuration File `.avie.json`

Example project-level configuration:

```json
{
  "rules": {
    "fanoutThreshold": 15,
    "enabled": ["AVIE001", "AVIE002", "AVIE003", "AVIE004"],
    "failOn": ["AVIE001", "AVIE002", "AVIE004"]
  },
  "suppressions": []
}
```

### 13.3 Suppression File `avie-suppress.json`

```json
{
  "suppressions": [
    {
      "key": "AVIE003:grdb",
      "reason": "GRDB is a full-featured database library. Its transitive depth is expected and reviewed.",
      "addedBy": "jane.doe",
      "addedAt": "2025-01-15T14:30:00Z"
    }
  ]
}
```

**Design rationale (from architecture review):** Keys are `ruleID:packageIdentity`. This means the suppression file does not need to be updated when the dependency graph changes in ways unrelated to the suppressed finding. This prevents the Git merge conflict problem that affects graph-state-based baseline files.

### 13.4 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success — no error-severity findings |
| 1 | Error-severity findings present |
| 2 | Avie internal error (can't resolve, parse failed, etc.) |
| 3 | Configuration error (.avie.json malformed) |

### 13.5 Versioning

Avie follows semantic versioning. The SARIF output schema version and JSON output schema version are independent of the CLI version and must be explicitly versioned in their output (`"schemaVersion": "1.0"`). Do not couple them.

---

## 14. Operational Edge Cases (Must Handle Before Ship)

These are the four cases from the architecture review that will break for real users if not handled explicitly. They must all be addressed before any public release.

### Edge Case 1: Package Not Yet Resolved

**Symptom:** `swift package show-dependencies` fails with an error about dependencies not being resolved.

**Handling:** `SPMResolver.validate()` must detect this case from stderr output and throw `ResolverError.dependenciesNotResolved` with a message instructing the user to run `swift package resolve` first. Never let the raw SPM error message reach the user — it's confusing.

### Edge Case 2: Xcode-Managed Projects

**Symptom:** The working directory contains a `.xcodeproj` file. `swift package` commands don't work here.

**Handling:** `SPMResolver.validate()` detects `.xcodeproj` and throws `ResolverError.xcodeProjectDetected` with a clear message that Xcode projects are not supported in v1, and that v2 support is planned. Never attempt to run `swift package` in an Xcode project directory and emit a cryptic error.

### Edge Case 3: CI Mode and Network Resolution

**Symptom:** In CI, `swift package show-dependencies` attempts to resolve new packages from the network, adding unpredictable latency or failing in air-gapped environments.

**Handling:** When `--ci` flag is passed, append `--disable-automatic-resolution` to the `swift package show-dependencies` invocation. Document this in the GitHub Action template.

### Edge Case 4: Stale `Package.resolved` Pins

**Symptom:** AVIE001 (Unreachable Pin) fires on packages that were recently removed from `Package.swift` but whose pins remain because `swift package resolve` hasn't been re-run since.

**Handling:** This is a legitimate finding — the pin IS stale and SHOULD be removed. The finding message must explain this clearly: *"This package is no longer declared in Package.swift. Run `swift package resolve` to clean up the lockfile."* Do not attempt to detect this case and suppress it — the correct developer action is to run resolve.

---

## 15. Testing Strategy

### Unit Test Matrix

Every module has a corresponding test target. Tests use the Fixture packages in `/Fixtures/`.

| Module | Test focus |
|--------|-----------|
| AvieCore | Codable round-trips, identity normalization, suppression key generation |
| AvieResolver | SPM output parsing with all fixture packages, error case coverage |
| AvieGraph | BFS/DFS correctness, path-finding, topological sort |
| AvieRules | Each rule fires on fixture packages where expected, does NOT fire where not expected |
| AvieDiff | Correct detection of added/removed packages, version changes, new findings |
| AvieOutput | Snapshot tests for terminal, JSON, SARIF outputs |

### Fixture Packages Required

```
Fixtures/simple-package/          # 3 direct deps, no issues
Fixtures/deep-transitive/         # 1 dep → 15 transitive (triggers AVIE003)
Fixtures/test-leakage/            # Quick in test target, reachable from prod (AVIE002)
Fixtures/binary-target/           # .binaryTarget dep (AVIE004)
Fixtures/unreachable-pin/         # Pin with no graph path (AVIE001)
Fixtures/clean-with-suppressions/ # Findings present but suppressed (no output expected)
```

Each fixture is a minimal but valid Swift package that reproduces exactly one finding scenario.

### Integration Tests

Integration tests execute the actual `avie audit` binary against fixture packages and assert on exit codes and stdout contents. These run as part of the CI pipeline on macOS only.

---

## 16. CI/CD & Distribution

### GitHub Actions Template

Provide this as `avie-action.yml` in the repository's `docs/` folder:

```yaml
name: Avie Dependency Audit

on:
  pull_request:
    paths:
      - 'Package.swift'
      - 'Package.resolved'

jobs:
  avie-audit:
    runs-on: macos-latest
    permissions:
      security-events: write  # Required for SARIF upload
      pull-requests: read

    steps:
      - uses: actions/checkout@v4

      - name: Install Avie
        run: brew install yourtap/tap/avie

      # Capture base branch snapshot
      - name: Snapshot base branch
        run: |
          git checkout ${{ github.base_ref }}
          avie snapshot --output base-snapshot.json --git-ref ${{ github.base_ref }} --ci

      # Capture PR branch snapshot
      - name: Snapshot PR branch
        run: |
          git checkout ${{ github.head_ref }}
          avie snapshot --output head-snapshot.json --git-ref ${{ github.head_ref }} --ci

      # Run diff and emit SARIF
      - name: Run Avie Diff
        run: |
          avie diff \
            --base base-snapshot.json \
            --head head-snapshot.json \
            --format sarif > avie-results.sarif

      # Upload SARIF for inline PR annotations
      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: avie-results.sarif
          category: avie-dependency-audit

      # Also run full audit for terminal output in logs
      - name: Full Audit (for logs)
        run: avie audit --ci --format terminal
```

### Homebrew Distribution

```ruby
# Formula/avie.rb
class Avie < Formula
  desc "Swift package graph diagnostics tool"
  homepage "https://github.com/yourusername/avie"
  url "https://github.com/yourusername/avie/archive/refs/tags/1.0.0.tar.gz"
  sha256 "..."
  license "MIT"

  depends_on xcode: ["14.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/avie"
  end

  test do
    system "#{bin}/avie", "--version"
  end
end
```

---

## 17. Phase Build Order

### Phase 1: Graph Engine Foundation

**Goal:** A working graph that can answer reachability questions.  
**Definition of Done:** `swift package avie-audit` resolves the graph and prints package count and depth. No rules yet. Zero output if graph resolves. Non-zero exit if graph fails to resolve.

Steps:
1. Set up repository structure and `Package.swift` as specified in Section 3
2. Implement all `AvieCore` domain models (Section 5)
3. Implement `SPMResolver` with all 4 operational edge cases handled (Section 6.1, Section 14)
4. Implement `SPMDependencyOutput` Codable models (Section 6.2)
5. Implement `DependencyTransformer` (Section 6.3)
6. Implement `ManifestReader` using `swift package dump-package` (Section 6.4)
7. Implement `DependencyGraph` (Section 7.1)
8. Implement `GraphTraversal` with BFS, DFS, shortest path, all paths (Section 7.2)
9. Write `AvieCoreTests`, `AvieResolverTests`, `AvieGraphTests` with fixture packages
10. Wire up `AuditCommand` skeleton that resolves and prints metadata only

**Tests that must pass before Phase 2:**
- `testResolverValidationRejectsXcodeProject()`
- `testResolverValidationRejectsUnresolvedPackage()`
- `testDependencyTransformerPreservesEdges()`
- `testBFSReachabilityIsCorrect()`
- `testShortestPathFindsMinimalPath()`
- `testAllPathsFindsAllRoutes()`

---

### Phase 2: Core Audit Rules

**Goal:** `avie audit` runs all 4 rules and produces terminal output. CI-ready.  
**Definition of Done:** Running `avie audit` on all fixture packages produces exactly the expected findings. Exit code 1 when error findings present.

Steps:
1. Implement `Rule` protocol (Section 8.1)
2. Implement `RuleContext` and `AvieConfiguration` loading
3. Implement `UnreachablePinRule` (AVIE001) (Section 8.2)
4. Implement `TestLeakageRule` (AVIE002) with graceful skip when no manifest (Section 8.3)
5. Implement `ExcessiveFanoutRule` (AVIE003) with configurable threshold (Section 8.4)
6. Implement `BinaryTargetRule` (AVIE004) (Section 8.5)
7. Implement `RuleEngine` orchestrator (Section 8.6)
8. Implement `TerminalFormatter` (Section 10.2)
9. Implement `JSONFormatter` (Section 10.3)
10. Implement `SARIFFormatter` (Section 10.4)
11. Implement `SuppressionFile` loading and `SuppressCommand`
12. Implement `ExplainCommand`
13. Write `AvieRulesTests` for all 4 rules against fixture packages
14. Write `AvieOutputTests` with snapshot tests for all 3 formatters

**Tests that must pass before Phase 3:**
- `testAVIE001FiresOnUnreachablePin()`
- `testAVIE001DoesNotFireOnReachablePackage()`
- `testAVIE002FiresOnTestLeakage()`
- `testAVIE002SkipsGracefullyWithoutManifest()`
- `testAVIE003FiresWhenFanoutExceedsThreshold()`
- `testAVIE003RespectsConfiguredThreshold()`
- `testAVIE004FiresOnBinaryTarget()`
- `testSuppressionFileSilencesFindings()`
- `testExitCode1WhenErrorFindingsPresent()`
- `testExitCode0WhenOnlyWarnings()`
- `testSARIFOutputIsValidSchema()`

---

### Phase 3: PR Diff Mode (Flagship Feature)

**Goal:** `avie diff --base base.json --head head.json` produces a full diff report in all formats. GitHub Action template works end-to-end.  
**Definition of Done:** A simulated PR that adds a new dep producing AVIE003 is correctly detected in diff mode. SARIF output passes GitHub SARIF schema validation.

Steps:
1. Implement `GraphSnapshot` model (Section 9.1)
2. Implement `DiffEngine` (Section 9.2)
3. Implement `SnapshotCommand` (Section 11.3)
4. Implement `DiffCommand` (Section 11.4)
5. Add diff formatting to `TerminalFormatter`, `JSONFormatter`, `SARIFFormatter`
6. Write `AvieDiffTests` with before/after fixture scenarios
7. Implement `AviePlugin` SPM Command Plugin (Section 12)
8. Write GitHub Action template (Section 16)
9. Write Homebrew formula (Section 16)
10. Write README.md

**Tests that must pass for 1.0 release:**
- `testDiffDetectsNewDirectDependency()`
- `testDiffDetectsNewTransitiveDependencies()`
- `testDiffDetectsVersionChange()`
- `testDiffDetectsNewBinaryTarget()`
- `testDiffExitsNonZeroOnBlockingIssues()`
- `testDiffReportsResolvedFindings()`
- `testSARIFDiffPassesSchemaValidation()`
- Full integration test: `avie snapshot` + `avie diff` pipeline on fixture packages

---

## 18. Appendix: Key Design Decisions Log

This section documents every contested decision, why it was made, and who raised the concern. Claude Code must treat these as final unless explicitly reversed by the developer.

| Decision | Chosen | Rejected | Rationale |
|----------|--------|----------|-----------|
| Source scanning in v1 | Drop entirely | SwiftSyntax / SwiftIndexStore | SwiftIndexStore requires prior build (destroys DevEx). SwiftSyntax produces false positives. Graph-only rules cover highest-value findings. Source evidence is v2. |
| Primary data source | `swift package show-dependencies --format json` | `Package.resolved` | Package.resolved has no graph edges — it's a flat pin list. show-dependencies is SPM's own output and contains the full edge set. |
| Plugin type | Command Plugin | Build Tool Plugin | Build Tool Plugins run on every build, adding latency. Commands run intentionally. |
| Baseline mechanism | Identity-keyed suppression file | Full graph-state baseline | Graph-state baseline causes Git merge conflicts. Identity-keyed keys are stable across unrelated graph changes. |
| "Zero false positives" claim | Never use this phrase | Use it in marketing | Stale pins and other edge cases can produce unexpected findings. "Graph-provable findings" is accurate. |
| Duplicate capability rule | Dropped | Implement with hardcoded taxonomy | Requires maintaining a massive package-to-category database. Impossible to maintain long-term for a solo developer. |
| Fan-out threshold | Configurable, default 10 | Hardcoded | Different project types have legitimately different standards. Hardcoded threshold is wrong for ~50% of users. |
| Xcode project support | Explicitly out of scope v1 | Implement in v1 | `swift package` commands don't work in .xcodeproj directories. Requires separate resolution path. Planned v2. |
| Local audit mode | Keep fully functional | Replace entirely with diff mode | Local audit is valuable for understanding current graph state. Diff mode is optimal for CI. Both are needed. |
| Language in output | "unreachable", "graph-provable" | "dead", "unused", "bloat" | "Unused" implies semantic proof. Avie proves graph reachability, not semantic necessity. Precision is required for credibility. |
| Test for false positives | Explicit fixture packages per case | Rely on unit tests alone | Integration tests against fixture packages catch real-world edge cases that unit tests miss. |
| SARIF output | Mandatory v1 | Terminal-only in v1, SARIF in v2 | GitHub CI annotation integration requires SARIF. Terminal-only output means CI teams need custom parsers. Non-negotiable. |
