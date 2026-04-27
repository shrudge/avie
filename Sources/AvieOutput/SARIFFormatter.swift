import Foundation
import AvieCore
import AvieRules
import AvieDiff

/// Produces SARIF 2.1.0 output for GitHub Code Scanning integration.
///
/// Bug 10 Fix: driver.rules now uses RuleMetadata to populate human-readable
/// name, shortDescription, and fullDescription for each rule. The GitHub
/// Security tab displays these strings to developers — "AVIE001" is useless,
/// "Unreachable Pinned Package" is actionable.
public struct SARIFFormatter: OutputFormatter {
    public init() {}

    public func format(_ findings: [Finding]) throws -> String {
        let results = findings.map { finding -> [String: Any] in
            let level: String
            switch finding.severity {
            case .error:   level = "error"
            case .warning: level = "warning"
            case .note:    level = "note"
            }

            return [
                "ruleId": finding.ruleID.rawValue,
                "level": level,
                "message": ["text": finding.summary + " " + finding.detail],
                "locations": [
                    [
                        "physicalLocation": [
                            "artifactLocation": ["uri": "Package.swift"],
                            "region": ["startLine": 1]
                        ]
                    ]
                ] as [[String: Any]]
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
                "defaultConfiguration": ["level": meta.sarifLevel]
            ]
        }

        let run: [String: Any] = [
            "tool": [
                "driver": [
                    "name": "Avie",
                    "version": avieToolVersion,
                    "informationUri": "https://github.com/TODO/avie",
                    "rules": rules
                ]
            ],
            "results": results
        ]

        let sarif: [String: Any] = [
            "version": "2.1.0",
            "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
            "runs": [run]
        ]

        let data = try JSONSerialization.data(withJSONObject: sarif, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public func format(diff: DiffEngine.DiffResult) throws -> String {
        return try format(diff.newFindings)
    }
}
