import Foundation
import AvieCore
import AvieDiff

public struct SARIFFormatter: OutputFormatter {
    public init() {}

    public func format(_ findings: [Finding]) throws -> String {
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
                "message": [
                    "text": finding.summary
                ],
                "locations": [] as [[String: Any]] // empty array — no file locations in graph-only rules
            ]
        }

        let run: [String: Any] = [
            "tool": [
                "driver": [
                    "name": "Avie",
                    "version": "1.0.0",
                    "rules": [] as [[String: Any]]
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
