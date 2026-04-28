import AvieCore
import AvieRules
import AvieDiff

public protocol OutputFormatter {
    func format(_ result: RuleEngine.AnalysisResult) throws -> String
    func format(_ diff: DiffEngine.DiffResult) throws -> String
}

public struct TerminalFormatter: OutputFormatter {
    private let useColor: Bool

    public init(useColor: Bool = true) {
        // TTY detection logic omitted, just simple passing param
        self.useColor = useColor
    }

    public func format(_ result: RuleEngine.AnalysisResult) throws -> String {
        var output = ""
        
        let bold = useColor ? "\u{001B}[1m" : ""
        let dim = useColor ? "\u{001B}[2m" : ""
        let reset = useColor ? "\u{001B}[0m" : ""
        let green = useColor ? "\u{001B}[32m" : ""

        output += "\(bold)Avie Dependency Graph Audit\(reset)\n"
        output += "\(dim)─────────────────────────────\(reset)\n"
        output += "\(dim)Packages: \(result.metadata.totalPackages) total, \(result.metadata.directDependencies) direct\(reset)\n"
        output += "\(dim)Max depth: \(result.metadata.transitiveDepth)\(reset)\n\n"

        let findings = result.findings

        guard !findings.isEmpty else {
            return output + "\(green)✓ No issues found. The dependency graph is clean.\(reset)\n"
        }
        
        let errors = findings.filter { $0.severity == .error }
        let warnings = findings.filter { $0.severity == .warning }
        let notes = findings.filter { $0.severity == .note }

        let sortedFindings = errors + warnings + notes

        for finding in sortedFindings {
            let colorCode: String
            let icon: String
            switch finding.severity {
            case .error:
                colorCode = "\u{001B}[31m" // Red
                icon = "✕"
            case .warning:
                colorCode = "\u{001B}[33m" // Yellow
                icon = "⚠"
            case .note:
                colorCode = "\u{001B}[34m" // Blue
                icon = "ℹ"
            }
            
            output += "\(colorCode)\(icon) \(finding.severity.rawValue.uppercased())\u{001B}[0m: [\(finding.ruleID.rawValue)] in \u{001B}[1m\(finding.affectedPackage)\u{001B}[0m\n"
            output += "  \(finding.summary)\n"
            
            let pathString = finding.graphPath.map { $0.value }.joined(separator: " → ")
            output += "  Path: \(pathString)\n\n"
        }
        
        output += "Found \(findings.count) issue(s) (\(errors.count) errors, \(warnings.count) warnings, \(notes.count) notes).\n"

        return output
    }

    public func format(_ diff: DiffEngine.DiffResult) throws -> String {
        var lines: [String] = []

        let red = useColor ? "\u{001B}[31m" : ""
        let yellow = useColor ? "\u{001B}[33m" : ""
        let green = useColor ? "\u{001B}[32m" : ""
        let cyan = useColor ? "\u{001B}[36m" : ""
        let bold = useColor ? "\u{001B}[1m" : ""
        let reset = useColor ? "\u{001B}[0m" : ""
        let dim = useColor ? "\u{001B}[2m" : ""

        // For non-color mode
        // Note: I will safely use the color constants directly as TerminalFormatter in its current form hasn't been reconfigured.
        // Wait, TerminalFormatter doesn't have useColor configured in this file currently. I will redefine them.
        
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
                let sevColor = finding.severity == .error ? red : (finding.severity == .warning ? yellow : cyan)
                lines.append(formatFinding(finding, prefix: "\(sevColor)\(finding.severity.rawValue)\(reset)", dim: dim, reset: reset, cyan: cyan))
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

    private func formatFinding(_ finding: Finding, prefix: String, dim: String, reset: String, cyan: String) -> String {
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
