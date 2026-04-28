import AvieCore
import AvieDiff
import AvieGraph
import AvieRules
import Foundation

/// Produces SARIF 2.1.0 output for GitHub Code Scanning integration.
///
/// Bug 10 Fix: driver.rules now uses RuleMetadata to populate human-readable
/// name, shortDescription, and fullDescription for each rule. The GitHub
/// Security tab displays these strings to developers — "AVIE001" is useless,
/// "Unreachable Pinned Package" is actionable.
public struct SARIFFormatter: OutputFormatter {
    public init() {}

    public func format(_ result: RuleEngine.AnalysisResult) throws -> String {
        let findings = result.findings
        let results = findings.map { finding -> [String: Any] in
            let level: String
            switch finding.severity {
            case .error: level = "error"
            case .warning: level = "warning"
            case .note: level = "note"
            }

            return [
                "ruleId": finding.ruleID.rawValue,
                "level": level,
                "message": ["text": finding.summary + " " + finding.detail],
                "locations": [
                    [
                        "physicalLocation": [
                            "artifactLocation": ["uri": "Package.swift"],
                            "region": ["startLine": 1],
                        ]
                    ]
                ] as [[String: Any]],
            ]
        }

        // Bug 10 Fix: populate rules with human-readable metadata from RuleMetadata.
        let rules: [[String: Any]] = RuleID.allCases.map { ruleID in
            let meta = RuleMetadata.info(for: ruleID)
            return [
                "id": ruleID.rawValue,
                "name": meta.name,
                "shortDescription": ["text": meta.shortDescription],
                "fullDescription": ["text": meta.fullDescription],
                "defaultConfiguration": ["level": meta.sarifLevel],
            ]
        }

        let run: [String: Any] = [
            "tool": [
                "driver": [
                    "name": "Avie",
                    "version": avieToolVersion,
                    "informationUri": "https://github.com/shrudge/avie",
                    "rules": rules,
                ]
            ],
            "results": results,
        ]

        let sarif: [String: Any] = [
            "version": "2.1.0",
            "$schema":
                "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
            "runs": [run],
        ]

        let data = try JSONSerialization.data(
            withJSONObject: sarif, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public func format(_ diff: DiffEngine.DiffResult) throws -> String {
        // Wrap new findings in a dummy result for SARIF formatting
        let rootID = PackageIdentity("diff")
        let rootPkg = ResolvedPackage(
            id: rootID, url: "", version: "0.0.0", name: "diff", directDependencies: [],
            isRoot: true, containsBinaryTarget: false)
        let dummyGraph = try DependencyGraph(packages: [rootID: rootPkg])
        let result = RuleEngine.AnalysisResult(
            findings: diff.newFindings,
            executedRules: [],
            skippedRules: [:],
            graph: dummyGraph,
            metadata: .init(
                totalPackages: 0,
                directDependencies: 0,
                transitiveDepth: 0,
                analysisDate: Date(),
                packageDirectory: ""
            )
        )
        return try format(result)
    }
}
