import XCTest
@testable import AvieOutput
@testable import AvieCore
@testable import AvieRules
@testable import AvieGraph

final class AvieOutputTests: XCTestCase {
    
    private var mockFindings: [Finding] {
        return [
            Finding(
                ruleID: .unreachablePin,
                severity: .error,
                confidence: .proven,
                summary: "Package 'foo' is pinned but unreachable.",
                detail: "Detail foo",
                graphPath: [PackageIdentity("root"), PackageIdentity("foo")],
                suggestedAction: "Drop it like it's hot",
                affectedPackage: PackageIdentity("foo")
            ),
            Finding(
                ruleID: .excessiveFanout,
                severity: .warning,
                confidence: .proven,
                summary: "'bar' has high fanout.",
                detail: "Detail bar",
                graphPath: [PackageIdentity("root"), PackageIdentity("bar")],
                suggestedAction: "Simplify",
                affectedPackage: PackageIdentity("bar")
            )
        ]
    }

    private var mockResult: RuleEngine.AnalysisResult {
        let rootID = PackageIdentity("root")
        let pkgID1 = PackageIdentity("foo")
        let pkgID2 = PackageIdentity("bar")
        
        let root = ResolvedPackage(id: rootID, url: "", version: "1.0.0", name: "root", directDependencies: [pkgID1, pkgID2], isRoot: true)
        let foo = ResolvedPackage(id: pkgID1, url: "", version: "1.0.1", name: "foo", directDependencies: [])
        let bar = ResolvedPackage(id: pkgID2, url: "", version: "2.0.0", name: "bar", directDependencies: [])
        
        let graph = try! DependencyGraph(packages: [
            rootID: root,
            pkgID1: foo,
            pkgID2: bar
        ])

        return RuleEngine.AnalysisResult(
            findings: mockFindings,
            executedRules: [.unreachablePin, .excessiveFanout],
            skippedRules: [:],
            graph: graph,
            metadata: .init(
                totalPackages: 3,
                directDependencies: 2,
                transitiveDepth: 1,
                analysisDate: Date(),
                packageDirectory: "/tmp/mock"
            )
        )
    }
    
    func testTerminalFormatter() throws {
        let formatter = TerminalFormatter()
        let result = try formatter.format(mockResult)
        
        // Assert strings exist
        XCTAssertTrue(result.contains("AVIE001"))
        XCTAssertTrue(result.contains("AVIE003"))
        XCTAssertTrue(result.contains("ERROR"))
        XCTAssertTrue(result.contains("WARNING"))
        XCTAssertTrue(result.contains("Package 'foo' is pinned but unreachable."))
        XCTAssertTrue(result.contains("'bar' has high fanout."))
        XCTAssertTrue(result.contains("Packages: 3 total"))
    }
    
    func testJSONFormatter() throws {
        let formatter = JSONFormatter()
        let result = try formatter.format(mockResult)
        
        let data = result.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["schemaVersion"] as? String, "1.0")
        
        let findings = json?["findings"] as? [[String: Any]]
        XCTAssertEqual(findings?.count, 2)
        
        let summary = json?["summary"] as? [String: Any]
        XCTAssertEqual(summary?["errors"] as? Int, 1)
        XCTAssertEqual(summary?["warnings"] as? Int, 1)
    }
    
    func testSARIFOutputIsValidSchema() throws {
        let formatter = SARIFFormatter()
        let result = try formatter.format(mockResult)
        
        let data = result.data(using: .utf8)!
        let sarifObj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertNotNil(sarifObj)
        XCTAssertEqual(sarifObj?["version"] as? String, "2.1.0")
        XCTAssertNotNil(sarifObj?["$schema"])
        
        let runs = sarifObj?["runs"] as? [[String: Any]]
        XCTAssertNotNil(runs)
        XCTAssertEqual(runs?.count, 1)
        
        let tool = runs?[0]["tool"] as? [String: Any]
        let driver = tool?["driver"] as? [String: Any]
        XCTAssertEqual(driver?["name"] as? String, "Avie")
        
        let results = runs?[0]["results"] as? [[String: Any]]
        XCTAssertEqual(results?.count, 2)
        
        let levels = results?.compactMap { $0["level"] as? String }
        XCTAssertTrue(levels?.contains("error") == true)
        XCTAssertTrue(levels?.contains("warning") == true)
    }
}
