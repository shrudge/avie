# Avie

Avie is a strict, graph-based Swift package dependency audit tool. 
It analyzes the output of SPM to find unreachable pins, test framework leakage, excessive transitive fan-out, and binary targets. 
Avie guarantees **graph-provable findings** without relying on source code scanning or heuristics.

## Features

- **Unreachable Pins (AVIE001):** Detects packages in `Package.resolved` that have no path from the root project.
- **Test Leakage (AVIE002):** Detects when test-only frameworks (like Quick or Nimble) become reachable from non-test targets.
- **Excessive Fan-out (AVIE003):** Detects when a single direct dependency introduces an excessive number of transitive dependencies (configurable).
- **Binary Target Detected (AVIE004):** Warns on closed-source binary dependencies (XCFrameworks) which cannot be source-audited.

## Installation

```bash
brew install yourtap/tap/avie
```

Alternatively, build from source:
```bash
git clone https://github.com/yourusername/avie.git
cd avie
swift build -c release
```

## Usage

### Local Audit
Run a local audit to view the current graph state in your terminal:
```bash
avie audit --path /path/to/project --format terminal
```

### Path Explanation
Wondering why a package is being pulled in?
```bash
avie explain some-package-name
```
This will print all graph paths from the root to `some-package-name`.

### PR Diff Mode (CI)
Avie is designed for strict continuous integration enforcement. It compares the dependency graph of your PR branch against the base branch and highlights *only the newly introduced issues*.

1. Capture base snapshot: `avie snapshot --output base.json`
2. Capture PR snapshot: `avie snapshot --output head.json`
3. Compare: `avie diff --base base.json --head head.json`

Check out `docs/avie-action.yml` for a fully functional GitHub Actions template that integrates with GitHub's CodeQL SARIF annotations for inline PR feedback.

## Configuration

Configure Avie by creating an `.avie.json` file in your package directory:
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

## Suppression

Sometimes you need to suppress findings. Avie uses durable suppressions that don't cause merge conflicts.
```bash
avie suppress AVIE003:some-package --reason "This is expected."
```
This amends `avie-suppress.json`.

## Architecture & Integration
Avie integrates directly via SPM Command Plugins:
```bash
swift package avie-audit
```

For full architectural details, see `AVIE_ARCHITECTURE.md`.
