# Avie

Strict, graph-provable dependency auditing for Swift packages.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![SPM compatible](https://img.shields.io/badge/SPM-compatible-brightgreen)

Avie runs `swift package show-dependencies` and `swift package dump-package`, builds a directed dependency graph, and evaluates four deterministic rules against it. Every finding is graph-provable — no heuristics, no source scanning.

---

## Installation

### Homebrew

```sh
# TODO: configure your tap and replace the line below
brew install <your-tap>/avie
```

### Build from source

Requirements: macOS 13+, Swift 5.9 / Xcode 14+. Linux is not supported.

```sh
git clone https://github.com/<your-username>/avie.git
cd avie
swift build -c release
cp .build/release/avie /usr/local/bin/avie
```

### SPM Command Plugin

Add Avie as a dev dependency and run the plugin directly:

```swift
// In your Package.swift
.package(url: "https://github.com/<your-username>/avie.git", from: "1.0.0")
```

```sh
swift package avie-audit
swift package avie-audit --format json
swift package avie-audit --ci
```

---

## Quick Start

```sh
# In any Swift package directory
avie audit

# Diff mode for PR analysis
avie diff --base base-snapshot.json --head head-snapshot.json

# Explain why a package is in the graph
avie explain swift-argument-parser

# Suppress a finding
avie suppress --rule AVIE003 --package grdb --reason "GRDB fanout is expected and reviewed"
```

---

## Commands Reference

### `avie audit`

Runs all enabled rules against the current package graph.

```
avie audit [options]

Options:
  -p, --path <path>        Path to package directory (default: .)
      --format <format>    Output format: terminal, json, sarif (default: terminal)
      --ci                 Disable automatic dependency resolution (for CI environments)
      --no-color           Disable ANSI color output
      --no-fail            Exit 0 even if error-severity findings are present
  -h, --help               Show help
```

**Examples:**

```sh
avie audit --format sarif > results.sarif
avie audit --ci --no-color
avie audit --no-fail   # informational run — always exits 0
```

---

### `avie diff`

Compares two graph snapshots produced by `avie snapshot`. Reports only newly introduced issues.

```
avie diff [options]

Options:
      --base <path>        Base branch snapshot JSON (required)
      --head <path>        Head (PR) branch snapshot JSON (required)
      --format <format>    Output format: terminal, json, sarif (default: terminal)
      --no-color           Disable ANSI color output
  -h, --help               Show help
```

**Examples:**

```sh
avie snapshot --output base.json
# ... make changes ...
avie snapshot --output head.json
avie diff --base base.json --head head.json
avie diff --base base.json --head head.json --format sarif > pr-diff.sarif
```

---

### `avie snapshot`

Captures the current graph state and audit findings to a JSON file for later comparison.

```
avie snapshot [options]

Options:
  -p, --path <path>        Path to package directory (default: .)
  -o, --output <path>      Output JSON path (default: avie-snapshot.json)
      --git-ref <ref>      Git ref label embedded in snapshot (e.g. branch name)
      --ci                 Disable automatic dependency resolution
  -h, --help               Show help
```

---

### `avie explain`

Prints all dependency paths from the root to a named package.

```
avie explain <package-identity> [options]

Arguments:
  <package-identity>       Package identity to explain (e.g. swift-argument-parser)

Options:
  -p, --path <path>        Path to package directory (default: .)
      --ci                 Disable automatic dependency resolution
  -h, --help               Show help
```

**Example:**

```sh
avie explain grdb
# Package: GRDB
# Version: 6.29.3
# URL: https://github.com/groue/GRDB.swift
# ───────────────────────────
# 2 path(s) to GRDB (showing up to 10):
#   1. root → my-app-target → grdb
#   2. root → some-library → grdb
```

---

### `avie suppress`

Adds an entry to `avie-suppress.json` to silence a specific finding indefinitely.

```
avie suppress [options]

Options:
      --rule <id>          Rule ID to suppress (e.g. AVIE001) (required)
      --package <identity> Package identity to suppress (e.g. grdb) (required)
  -r, --reason <reason>    Reason for suppression — mandatory, must be non-empty (required)
      --who <name>         Author name (defaults to $USER)
  -h, --help               Show help
```

**Example:**

```sh
avie suppress --rule AVIE003 --package grdb \
  --reason "GRDB is a full-featured database. Its transitive depth is expected and reviewed."
```

Suppressions are keyed as `ruleID:packageIdentity`. They survive graph changes because they identify the specific rule-package pair, not a graph snapshot.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0`  | Clean — no error-severity findings on configured `failOn` rules |
| `1`  | Error-severity findings are present (suppressed `--no-fail` to override) |
| `2`  | Fatal error — resolver failed, graph could not be built, or parse error |
| `3`  | Configuration error — `.avie.json` is malformed |

Use exit codes in CI scripts:

```sh
avie audit || { echo "Dependency issues found"; exit 1; }

# Informational — always passes
avie audit --no-fail; echo "Audit complete (exit 0 regardless)"
```

---

## Audit Rules

### AVIE001 — Unreachable Pins

**Severity:** error  
**Confidence:** proven

A package is present in `Package.resolved` but no target in `Package.swift` depends on it, directly or transitively.

**Trigger:** Package exists in the resolved pin list but has no path from the root through any production or test target.

**Fix:** Remove the package from your `Package.swift` dependencies and run `swift package resolve`.

**Note:** If you just removed a package from `Package.swift`, `swift package resolve` must be run before Avie is invoked. Until then, the stale pin remains in `Package.resolved` and AVIE001 will fire. This is expected behavior — run `swift package resolve` first.

---

### AVIE002 — Test Leakage

**Severity:** error  
**Confidence:** heuristic

A package that is only directly depended upon by a test target is transitively reachable from a production target.

**Trigger:** A package is declared only in test target dependencies, but a production target pulls it in transitively through another dependency.

**Fix:** Audit the direct production dependency that is pulling in the test library. You may need to update that library to make the test dependency a dev-only dependency, or remove the test library from your graph if it is unused.

**Note:** AVIE002 requires manifest data from `swift package dump-package`. If that command fails, this rule is silently skipped. All other rules continue.

---

### AVIE003 — Excessive Transitive Fan-out

**Severity:** warning  
**Confidence:** proven

A single direct dependency introduces more transitive packages than the configured threshold.

**Default threshold:** 10 packages. Configurable via `.avie.json`.

**Trigger:** `transitiveCount(dep) > fanoutThreshold` for any direct dependency of the root.

**Fix:** Evaluate whether the dependency can be replaced with a lighter alternative, whether you use only a small subset of its API, or raise the threshold in `.avie.json` if the fanout is acceptable.

**Example config to raise threshold:**

```json
{
  "rules": {
    "fanoutThreshold": 20
  }
}
```

---

### AVIE004 — Binary Target Detected

**Severity:** warning  
**Confidence:** proven

A package in the graph includes a binary target (XCFramework).

**Trigger:** `swift package show-dependencies` reports a package with one or more binary targets.

**Fix:** Verify the binary target is from a trusted source. If a source-available alternative exists, prefer it. Suppress this finding if the binary is intentional and reviewed.

**Note:** Binary targets limit platform portability and cannot be audited for security or license compliance.

---

## Configuration

### `.avie.json`

Place in your package root. All fields are optional.

```json
{
  "rules": {
    "fanoutThreshold": 10,
    "enabled": ["AVIE001", "AVIE002", "AVIE003", "AVIE004"],
    "failOn": ["AVIE001", "AVIE002", "AVIE004"]
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `rules.fanoutThreshold` | `Int` | `10` | Max transitive deps before AVIE003 fires |
| `rules.enabled` | `[String]` | all four | Which rules to run |
| `rules.failOn` | `[String]` | AVIE001, AVIE002, AVIE004 | Rules that produce exit code 1 |

---

### `avie-suppress.json`

Managed by `avie suppress`. Commit this file to version control.

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

**Key format:** `RULEIO:package-identity`

Keys are deterministic and merge-conflict-safe. They identify a specific rule-package pair, not a graph state. Reorganizing your package graph does not invalidate suppressions.

**Best practices:**
- Always provide a meaningful `--reason`. Empty reasons are rejected.
- Review suppressions periodically. If the underlying issue is fixed, remove the suppression.
- Suppressions are package-scoped, not version-scoped. A suppression for `grdb` applies to all versions.

---

## CI/CD Integration

See [`docs/avie-action.yml`](docs/avie-action.yml) for a complete GitHub Actions workflow template that:

- Runs on PRs that modify `Package.swift` or `Package.resolved`
- Captures base and head branch snapshots
- Runs `avie diff` in SARIF mode
- Uploads results to the GitHub Security tab for inline PR annotations

**Minimal PR diff workflow:**

```yaml
- name: Snapshot base branch
  run: |
    git checkout ${{ github.base_ref }}
    avie snapshot --output base.json --ci

- name: Snapshot PR branch
  run: |
    git checkout ${{ github.head_ref }}
    avie snapshot --output head.json --ci

- name: Diff
  run: avie diff --base base.json --head head.json --format sarif > avie.sarif

- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: avie.sarif
```

**CI mode (`--ci`):** Passes `--disable-automatic-resolution` to `swift package show-dependencies`. Use this in air-gapped environments or when you want to guarantee the graph state matches `Package.resolved` exactly without network access.

**Informational checks:** Use `--no-fail` to run Avie on every PR without blocking merges:

```sh
avie audit --ci --no-fail --format sarif > avie.sarif
```

---

## Troubleshooting

**AVIE001 fires after I removed a package from `Package.swift`**  
Run `swift package resolve` before running `avie audit`. The stale pin remains in `Package.resolved` until SPM updates it.

**Audit fails with a manifest error**  
`swift package dump-package` failed. Run it directly to see the error:

```sh
swift package dump-package
```

This only affects AVIE002 (Test Leakage). All other rules continue. If the error is persistent, check your `Package.swift` for syntax issues.

**Error: An Xcode project was detected**  
Avie v1 supports pure SPM packages only. Xcode project workspace support is planned for v2. Run `swift package` commands from the directory containing `Package.swift`, not the `.xcodeproj`.

**No color output in CI**  
Pass `--no-color` explicitly, or rely on CI environment detection. Terminal color codes are always safe to suppress in log files.

**`avie snapshot` fails with "dependencies not resolved"**  
Run `swift package resolve` first. In CI, verify your checkout step fetches the full history and resolves dependencies before the snapshot step.

---

## Development

### Running tests

```sh
swift test
```

### Fixture packages

Integration tests in `Tests/AvieResolverTests/` run against pre-baked fixture packages in `Tests/AvieResolverTests/Fixtures/`. Each fixture is a minimal Swift package that reproduces exactly one finding scenario:

| Fixture | Rule triggered |
|---------|---------------|
| `simple-package` | baseline — no findings |
| `unreachable-pin` | AVIE001 |
| `test-leakage` | AVIE002 |
| `deep-transitive` | AVIE003 |
| `binary-target` | AVIE004 |
| `diff-scenario` | snapshot/diff pipeline |

### Adding a new rule

1. Add a new `case` to `RuleID` in `Sources/AvieCore/Models/RuleID.swift`
2. Implement `Rule` protocol in `Sources/AvieRules/`
3. Register the case in `RuleEngine.instantiateRules(from:)`
4. Add a fixture package that reproduces the finding
5. Add tests to `Tests/AvieRulesTests/`

---

## Project Structure

```
Sources/
  AvieCore/       — shared models (Finding, ResolvedPackage, RuleID, configuration)
  AvieResolver/   — SPMResolver, ManifestReader, DependencyTransformer
  AvieGraph/      — DependencyGraph, GraphTraversal (BFS/DFS)
  AvieRules/      — Rule protocol, RuleEngine, AVIE001–AVIE004
  AvieDiff/       — GraphSnapshot, DiffEngine
  AvieOutput/     — TerminalFormatter, JSONFormatter, SARIFFormatter
  AvieCLI/        — entry point, all subcommands

Tests/
  AvieCoreTests/
  AvieResolverTests/    — includes Fixtures/
  AvieGraphTests/
  AvieRulesTests/
  AvieDiffTests/
  AvieOutputTests/

Plugins/
  AviePlugin/     — SPM Command Plugin (swift package avie-audit)

docs/
  avie-action.yml — GitHub Actions template

.github/
  workflows/
    release.yml   — binary release on version tags
```

---

## License

MIT. See LICENSE file.
