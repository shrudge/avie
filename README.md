# Avie

**Swift package graph diagnostics. Graph-provable findings. CI-native.**

[![Swift 5.9](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![Platform macOS 13+](https://img.shields.io/badge/Platform-macOS%2013%2B-lightgrey?style=flat)](https://developer.apple.com/macos)
[![License MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)](LICENSE)

Avie is a **Swift Package Manager dependency graph audit tool** for iOS and macOS teams. It surfaces structural problems in your `Package.swift` dependency graph — unreachable pins, test dependency leakage, excessive transitive fan-out, and binary target introductions — with findings that are provable from graph mathematics, not guesswork.

The flagship feature is **PR Diff Mode**: snapshot the dependency graph on the base branch, snapshot it on the PR branch, and compare. Any structural regression — a new binary target, a suddenly leaking test framework, a dependency that adds 20 transitive packages — is surfaced as a precise, actionable finding.

---

## Contents

1. [Why Avie](#why-avie)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [Audit Rules](#audit-rules)
5. [CLI Reference](#cli-reference)
6. [PR Diff Mode](#pr-diff-mode)
7. [Configuration](#configuration)
8. [Suppression](#suppression)
9. [Output Formats](#output-formats)
10. [CI/CD Integration](#cicd-integration)
11. [SPM Command Plugin](#spm-command-plugin)
12. [Architecture Notes](#architecture-notes)
13. [Known Limitations](#known-limitations)

---

## Why Avie

The Swift compiler and SPM's resolver prevent version conflicts. They do not prevent _structural_ problems:

| Problem | What it costs | How common |
|---------|---------------|-----------|
| Packages pinned in `Package.resolved` that no production target depends on | Slower `swift package resolve`, wasted lockfile space | Very common after refactors |
| Test frameworks (Quick, Nimble) reachable from production targets | Risk of test code in App Store builds | Subtle, hard to notice |
| One "lightweight" library that transitively pulls in 15 packages | Unexpected binary size increase, slower builds | Common with SDK-style packages |
| Binary XCFrameworks introduced silently in a PR | Security and license risk — no source to audit | The scariest one |

Avie catches all four. Its findings are **graph-provable**: derivable purely from dependency graph topology using BFS reachability, not from source scanning, not from heuristics. Either a node is reachable from the root or it is not. The math does not lie.

---

## Installation

### Homebrew

```sh
brew install shrudge/tap/avie
```

### Swift Package Manager (from source)

```sh
git clone https://github.com/shrudge/avie.git
cd avie
swift build -c release
cp .build/release/avie /usr/local/bin/avie
```

### SPM Command Plugin (use in your project)

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/shrudge/avie.git", from: "1.0.0")
```

Then invoke:

```sh
swift package avie-audit
```

---

## Quick Start

```sh
# Navigate to your Swift package
cd MyApp

# Run a full graph audit
avie audit

# Example output:
# Avie Dependency Graph Audit
# ─────────────────────────────
# Packages: 24 total, 6 direct
# Max depth: 4
#
# [error] [AVIE001] swift-log is pinned but unreachable from root
#   'swift-log' appears in Package.resolved but no path exists from root.
#   → Run `swift package resolve` to remove stale pins.
#   Suppress: avie suppress AVIE001:swift-log --reason "..."
#
# Summary: 1 error(s), 0 warning(s)
```

Exit codes: `0` = clean, `1` = error-severity findings, `2` = resolver failure, `3` = config malformed.

---

## Audit Rules

All four v1 rules are **graph-provable**: their findings are derivable from dependency graph topology alone. Avie v1 does not scan source files for `import` statements.

### AVIE001 — Unreachable Pin

**Severity:** Error  
**Confidence:** Proven

A package appears in `Package.resolved` but is not reachable from the root package via any dependency edge.

**Why this happens:**
- A dependency was removed from `Package.swift` but `swift package resolve` was not re-run
- `Package.resolved` is stale (lockfile not updated after manifest change)

**Action:** Run `swift package resolve`. The stale pin will be removed.

**Example finding:**
```
[error] [AVIE001] swift-log is pinned but unreachable from root
  'swift-log' (1.5.4) appears in the resolved dependency graph but
  no path exists from the root package to this dependency.
  → Run `swift package resolve` to remove stale pins, or check if
    this package was intentionally removed from Package.swift.
```

---

### AVIE002 — Test Leakage

**Severity:** Error  
**Confidence:** Proven (requires manifest data)

A package that is exclusively depended on by test targets is also transitively reachable from a production target's dependency graph.

**Why this matters:** Test frameworks (Quick, Nimble, ViewInspector) should never be compiled into App Store binaries. When they're transitively reachable from production targets, they risk being linked into release builds.

**Requires:** `swift package dump-package` output (collected automatically). If manifest parsing fails, AVIE002 is skipped and a note is emitted.

**Example finding:**
```
[error] [AVIE002] Test dependency 'quick' leaked into production graph.
  This package is only directly depended on by a test target, but is
  transitively reachable from a production target.
  → Check production dependencies. You may be importing a test library
    in production code.
```

---

### AVIE003 — Excessive Transitive Fan-out

**Severity:** Warning  
**Confidence:** Proven

A direct dependency of the root package transitively pulls in more packages than the configured threshold (default: 10).

**Why this matters:** A single "lightweight" library that pulls in 15 transitive packages can silently double your dependency graph. This rule is most valuable in **PR Diff Mode**, where it flags when a new dependency introduces excessive fan-out.

**Configuration:** Set `rules.fanoutThreshold` in `.avie.json` (default: `10`).

**Example finding:**
```
[warning] [AVIE003] Firebase introduces 23 transitive dependencies (threshold: 10)
  'Firebase' is a direct dependency that transitively pulls in 23 additional
  packages. Consider whether all 23 packages are genuinely needed.
  → Review whether 'Firebase' is being used for a narrow purpose that could
    be served by a lighter-weight package.
```

---

### AVIE004 — Binary Target Introduced

**Severity:** Error  
**Confidence:** Proven

A dependency in the graph contains a `.binaryTarget` declaration (XCFramework).

**Why this matters:** Binary targets cannot be audited for security vulnerabilities (no source), their code size contribution cannot be estimated without full compilation, and their licenses cannot be reviewed from source. Any binary target introduction requires explicit human review.

**Detection method:** Avie runs `swift package dump-package` in each dependency's local checkout path and inspects the `targets` array for entries with `type == "binary"`. This is manifest inspection, not URL pattern matching.

**Example finding:**
```
[error] [AVIE004] GoogleAnalytics contains a binary target (XCFramework)
  'GoogleAnalytics' contains a .binaryTarget declaration, meaning it
  distributes a pre-compiled XCFramework that cannot be source-audited.
  → Review the XCFramework source, license, and security posture.
    Add a suppression if this binary target is intentional and reviewed.
```

---

## CLI Reference

### `avie audit`

Run a full dependency graph audit on the current package.

```sh
avie audit [--path <path>] [--format <format>] [--ci] [--skip-binary-detection] [--no-color] [--no-fail]
```

| Flag | Description |
|------|-------------|
| `--path <path>` | Package directory (default: `.`) |
| `--format <format>` | `terminal` (default), `json`, or `sarif` |
| `--ci` | Append `--disable-automatic-resolution` to SPM calls (prevents network access in CI) |
| `--skip-binary-detection` | **Fast Mode**. Bypass binary target manifest inspection on large repositories |
| `--no-color` | Disable ANSI color output |
| `--no-fail` | Exit 0 even if error-severity findings are present |

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | No error-severity findings (warnings may be present) |
| `1` | One or more error-severity findings |
| `2` | Fatal error: resolver failed, package not found, or parse error |
| `3` | Configuration error: `.avie.json` is malformed |

---

### `avie snapshot`

Capture the current dependency graph state as a JSON file for later diff comparison.

```sh
avie snapshot [--path <path>] [--output <file>] [--git-ref <ref>] [--ci] [--skip-binary-detection]
```

| Option | Description |
|--------|-------------|
| `--path <path>` | Package directory (default: `.`) |
| `--output <file>` | Output path (default: `avie-snapshot.json`) |
| `--git-ref <ref>` | Git branch/SHA label for CI traceability |
| `--ci` | Disable automatic dependency resolution |
| `--skip-binary-detection` | **Fast Mode**. Bypass binary target manifest inspection on large repositories |

Snapshots include the full package graph, all audit findings, and the avie version that generated them.

---

### `avie diff`

Compare two snapshots and report what changed.

```sh
avie diff --base <base.json> --head <head.json> [--format <format>]
```

| Option | Description |
|--------|-------------|
| `--base <file>` | JSON snapshot from the base branch |
| `--head <file>` | JSON snapshot from the PR branch |
| `--format <format>` | `terminal` (default), `json`, or `sarif` |

Reports:
- Packages added / removed
- Version changes (numeric semver comparison — `10.0.0 > 2.0.0`)
- New direct dependencies and their transitive fan-out
- New binary targets introduced
- New audit findings that weren't in base
- Findings from base that were resolved in head

Exit code `1` if the diff has blocking issues (new binary targets or new error-severity findings).

---

### `avie explain`

Explain why a package is in the dependency graph.

```sh
avie explain <package-identity> [--path <path>]
```

Finds all paths from the root package to the named package, showing exactly what chain of dependencies pulls it in.

---

### `avie suppress`

Add a suppression entry to `avie-suppress.json`.

```sh
avie suppress <key> --reason <text> [--who <name>]
```

The key format is `RULE_ID:package-identity`, for example:

```sh
avie suppress AVIE003:grdb \
  --reason "GRDB is a full-featured database library. Transitive depth is expected and reviewed."
```

| Argument/Option | Description |
|-----------------|-------------|
| `<key>` | Positional: suppression key in format `AVIE003:package-identity` |
| `--reason <text>` | Mandatory. Non-empty reason for the suppression. |
| `--who <name>` | Author (defaults to `$USER` environment variable) |

---

## PR Diff Mode

PR Diff Mode is Avie's flagship feature. The workflow:

```sh
# On base branch
git checkout main
avie snapshot --output base.json --git-ref main --ci

# On PR branch
git checkout my-feature
avie snapshot --output head.json --git-ref my-feature --ci

# Compare
avie diff --base base.json --head head.json
```

**Sample diff output:**
```
Avie PR Diff Report
────────────────────
Package count: +3  |  Depth delta: +1

⚠ Binary targets introduced:
  + GoogleAnalytics (1.0.0) — XCFramework, cannot be source-audited

New direct dependencies:
  + Firebase 10.25.0 (+18 transitive)

New violations introduced:
  [error] [AVIE004] GoogleAnalytics contains a binary target (XCFramework)
    → Review the XCFramework source, license, and security posture.

✗ This PR introduces blocking dependency issues.
```

---

## Configuration

Create `.avie.json` in the package root to customize behavior:

```json
{
  "rules": {
    "fanoutThreshold": 15,
    "enabled": ["AVIE001", "AVIE002", "AVIE003", "AVIE004"],
    "failOn": ["AVIE001", "AVIE002", "AVIE004"]
  }
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `rules.fanoutThreshold` | `10` | Transitive dependency count that triggers AVIE003 |
| `rules.enabled` | All four | Rule IDs to run |
| `rules.failOn` | `AVIE001`, `AVIE002`, `AVIE004` | Rules that produce a non-zero exit code (AVIE003 is warning-only by default) |

All fields are optional. An absent `.avie.json` uses the defaults above.

---

## Suppression

Suppressions are stored in `avie-suppress.json` at the package root. Add them with `avie suppress`:

```sh
avie suppress AVIE003:grdb \
  --reason "GRDB is a full-featured database. Transitive depth is expected." \
  --who "jane.doe"
```

This writes:

```json
{
  "suppressions": [
    {
      "key": "AVIE003:grdb",
      "reason": "GRDB is a full-featured database. Transitive depth is expected.",
      "addedBy": "jane.doe",
      "addedAt": "2025-03-15T09:30:00Z"
    }
  ]
}
```

**Key design:** Suppression keys are `ruleID:packageIdentity`. They are identity-based, not graph-state-based. This means the suppression file remains stable when the graph changes in ways unrelated to the suppressed finding — no Git merge conflicts from baseline drift.

Commit `avie-suppress.json` to source control. Reviewers can audit every suppression: what was suppressed, why, by whom, and when.

---

## Output Formats

### Terminal (default)

Color-coded, human-readable output for local development. Auto-detects TTY; color is automatically disabled when output is piped. Use `--no-color` to disable explicitly.

### JSON (`--format json`)

Machine-readable output for custom CI tooling or dashboard integration. Schema:

```json
{
  "schemaVersion": "1.0",
  "metadata": {
    "totalPackages": 24,
    "directDependencies": 6,
    "transitiveDepth": 4,
    "analysisDate": "2025-03-15T09:30:00Z"
  },
  "findings": [
    {
      "ruleID": "AVIE001",
      "severity": "error",
      "confidence": "proven",
      "summary": "swift-log is pinned but unreachable from root",
      "detail": "...",
      "graphPath": [],
      "suggestedAction": "Run `swift package resolve` to remove stale pins.",
      "affectedPackage": "swift-log",
      "suppressionKey": "AVIE001:swift-log"
    }
  ],
  "summary": {
    "totalPackages": 24,
    "errors": 1,
    "warnings": 0,
    "passed": false
  }
}
```

### SARIF (`--format sarif`)

[SARIF 2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html) output for GitHub Code Scanning integration. When uploaded, findings appear as:
- Inline PR annotations on changed files
- Entries in the repository's **Security** tab
- Status checks on the PR

Upload with `github/codeql-action/upload-sarif@v3`.

---

## CI/CD Integration

Copy the following workflow to `.github/workflows/avie.yml` in your repository:

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
      security-events: write   # Required for SARIF upload
      pull-requests: read

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # Required for git checkout of base branch below

      - name: Install Avie
        run: brew install shrudge/tap/avie

      # Capture base branch snapshot
      - name: Snapshot base branch
        run: |
          git checkout ${{ github.base_ref }}
          avie snapshot \
            --output base-snapshot.json \
            --git-ref ${{ github.base_ref }} \
            --ci

      # Capture PR branch snapshot
      - name: Snapshot PR branch
        run: |
          git checkout ${{ github.head_ref }}
          avie snapshot \
            --output head-snapshot.json \
            --git-ref ${{ github.head_ref }} \
            --ci

      # Run diff and emit SARIF for GitHub Code Scanning
      - name: Run Avie Diff
        run: |
          avie diff \
            --base base-snapshot.json \
            --head head-snapshot.json \
            --format sarif > avie-results.sarif

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: avie-results.sarif
          category: avie-dependency-audit

      # Also run full audit for human-readable log output
      - name: Full Audit
        run: avie audit --ci --format terminal
```

**The `--ci` flag** appends `--disable-automatic-resolution` to all SPM calls, keeping CI runs deterministic and preventing unexpected network access.

---

## SPM Command Plugin

Avie ships as an SPM Command Plugin (`AviePlugin`). This lets you run audits without installing the CLI binary:

```sh
# Run in your project directory
swift package avie-audit

# With options
swift package avie-audit --format json
swift package avie-audit --ci
```

The plugin invokes `avie audit` with the package directory automatically set. It propagates the exit code, so `swift package avie-audit` will fail in CI when findings are present.

**Important:** Avie ships as a **Command Plugin**, not a Build Tool Plugin. It runs only when you invoke it intentionally — never automatically on `swift build` or `Cmd+B` in Xcode. This is by design.

---

## Architecture Notes

### Data Source

Avie uses `swift package show-dependencies --format json` as its primary data source. This is SPM's own output and contains the full dependency edge set. It does **not** use `Package.resolved` (a flat pin list with no graph edges).

The manifest (`swift package dump-package`) is used by AVIE002 (Test Leakage) to determine which targets are test targets, and for binary target detection (AVIE004).

### Graph-Provable Findings

Every finding Avie v1 emits is derivable from graph structure using BFS reachability. The claim is precisely: "this node is [not] reachable from the root node via these edges." No source scanning. No pattern matching. No heuristics.

This is documented in findings output as `"confidence": "proven"`.

### Identity Derivation

Package identities are derived from the source URL's last path component (with `.git` suffix stripped, lowercased). Example: `https://github.com/apple/swift-argument-parser.git` → `swift-argument-parser`. This matches SPM's own identity derivation.

### Version Comparison

`avie diff` uses numeric semantic version comparison (`major.minor.patch`). `10.0.0 > 2.0.0` is true. Pre-release suffixes (`1.0.0-beta`) are always considered older than the same version without them.

### Swift Toolchain Resolution

Avie resolves the `swift` executable at runtime via `xcrun -f swift`, then `which swift`, then falls back to `/usr/bin/swift`. This ensures correct behavior with Homebrew Swift installations and `xcode-select` alternate toolchains.

---

## Known Limitations

### v1 Explicit Non-Goals

| Limitation | Reason | Planned |
|------------|--------|---------|
| Xcode-managed projects (`.xcodeproj`) | `swift package` commands don't work in `.xcodeproj` directories | v2 |
| Source-level usage verification (`import` scanning) | SwiftIndexStore requires a prior build; SwiftSyntax has false positives | v2 |
| Linux targets | Avie's analyzer runs on macOS only in v1 | v2 |

### Xcode Projects

If your project uses `.xcodeproj` and depends on SPM for packages, Avie v1 cannot analyze it. The package dependencies are stored in a different location (`MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`) and `swift package show-dependencies` does not work in that directory structure.

Avie v1 supports **pure SPM packages** only — projects with a `Package.swift` at the root where `swift package resolve` works.

### Stale `Package.resolved`

AVIE001 (Unreachable Pin) fires on packages removed from `Package.swift` whose pins remain in `Package.resolved` because `swift package resolve` hasn't been re-run. This is a **legitimate finding**, not a false positive. The developer action is to run `swift package resolve` to clean up the lockfile.

### Language Precision

Avie uses precise language in all output:
- **Use:** "unreachable," "not reachable from root targets"
- **Never:** "dead," "unused," "bloat"

The distinction matters: "unused" implies semantic proof of non-usage. Avie proves graph reachability — a different and more precise claim.

---

## License

MIT — see [LICENSE](LICENSE).

---

*Avie v1.0.0 — graph-provable findings for Swift package graphs.*
