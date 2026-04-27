import XCTest
@testable import AvieOutput
@testable import AvieCore

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
    
    func testTerminalFormatter() throws {
        let formatter = TerminalFormatter()
        let result = try formatter.format(mockFindings)
        
        // Assert strings exist
        XCTAssertTrue(result.contains("AVIE001"))
        XCTAssertTrue(result.contains("AVIE003"))
        XCTAssertTrue(result.contains("ERROR"))
        XCTAssertTrue(result.contains("WARNING"))
        XCTAssertTrue(result.contains("Package 'foo' is pinned but unreachable."))
        XCTAssertTrue(result.contains("'bar' has high fanout."))
    }
    
    func testJSONFormatter() throws {
        let formatter = JSONFormatter()
        let result = try formatter.format(mockFindings)
        
        let data = result.data(using: .utf8)!
        let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        
        XCTAssertNotNil(jsonArray)
        XCTAssertEqual(jsonArray?.count, 2)
        
        XCTAssertTrue(result.contains("AVIE001"))
        XCTAssertTrue(result.contains("AVIE003"))
    }
    
    func testSARIFOutputIsValidSchema() throws {
        let formatter = SARIFFormatter()
        let result = try formatter.format(mockFindings)
        
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
