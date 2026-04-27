import AvieCore

public protocol OutputFormatter {
    func format(_ findings: [Finding]) throws -> String
}

public struct TerminalFormatter: OutputFormatter {
    public init() {}

    public func format(_ findings: [Finding]) throws -> String {
        guard !findings.isEmpty else {
            return "\u{001B}[32m✓ No issues found. The dependency graph is clean.\u{001B}[0m\n"
        }

        var output = ""
        
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
}
