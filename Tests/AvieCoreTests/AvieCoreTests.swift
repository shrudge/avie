import XCTest
@testable import AvieCore

final class AvieCoreTests: XCTestCase {

    func testPackageIdentityNormalizesCase() {
        let id = PackageIdentity("Swift-Argument-Parser")
        XCTAssertEqual(id.value, "swift-argument-parser")
    }

    func testPackageIdentityStripsGitSuffix() {
        let id = PackageIdentity("swift-log.git")
        XCTAssertEqual(id.value, "swift-log")
    }

    func testPackageIdentityEquality() {
        let a = PackageIdentity("MyPackage.git")
        let b = PackageIdentity("mypackage")
        XCTAssertEqual(a, b)
    }

    func testFindingSuppressionKey() {
        let finding = Finding(
            ruleID: .unreachablePin,
            severity: .error,
            confidence: .proven,
            summary: "test",
            detail: "test detail",
            graphPath: [],
            suggestedAction: "fix it",
            affectedPackage: PackageIdentity("swift-log")
        )
        XCTAssertEqual(finding.suppressionKey, "AVIE001:swift-log")
    }

    func testResolvedPackageCodableRoundTrip() throws {
        let pkg = ResolvedPackage(
            id: PackageIdentity("test-pkg"),
            url: "https://github.com/test/test-pkg",
            version: "1.0.0",
            name: "test-pkg",
            directDependencies: [PackageIdentity("dep-a")],
            isRoot: false
        )
        let data = try JSONEncoder().encode(pkg)
        let decoded = try JSONDecoder().decode(ResolvedPackage.self, from: data)
        XCTAssertEqual(decoded.id, pkg.id)
        XCTAssertEqual(decoded.version, "1.0.0")
        XCTAssertEqual(decoded.directDependencies.count, 1)
    }
}
