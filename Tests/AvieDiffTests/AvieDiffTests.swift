import XCTest
@testable import AvieCore
@testable import AvieDiff
@testable import AvieOutput

final class AvieDiffTests: XCTestCase {

    private let rootID = PackageIdentity("root")
    private let pkgA = PackageIdentity("package-a")
    private let pkgB = PackageIdentity("package-b")
    private let pkgC = PackageIdentity("package-c")

    private func makePackage(_ id: PackageIdentity, v: String = "1.0.0", isRoot: Bool = false, deps: [PackageIdentity] = [], isBinary: Bool = false) -> ResolvedPackage {
        ResolvedPackage(id: id, url: "", version: v, name: id.value, directDependencies: deps, isRoot: isRoot, containsBinaryTarget: isBinary)
    }

    func testDiffDetectsNewDirectDependency() {
        let baseRoot = makePackage(rootID, isRoot: true, deps: [pkgA])
        let baseA = makePackage(pkgA)
        let baseSnapshot = GraphSnapshot(
            packages: [rootID: baseRoot, pkgA: baseA],
            rootIdentity: rootID,
            findings: [], gitRef: nil, avieVersion: "1.0"
        )

        let headRoot = makePackage(rootID, isRoot: true, deps: [pkgA, pkgB])
        let headB = makePackage(pkgB)
        let headSnapshot = GraphSnapshot(
            packages: [rootID: headRoot, pkgA: baseA, pkgB: headB],
            rootIdentity: rootID,
            findings: [], gitRef: nil, avieVersion: "1.0"
        )

        let diff = DiffEngine().diff(base: baseSnapshot, head: headSnapshot)

        XCTAssertTrue(diff.newDirectDependencies.contains(where: { $0.id == pkgB }))
        XCTAssertTrue(diff.addedPackages.contains(where: { $0.id == pkgB }))
    }

    func testDiffDetectsNewTransitiveDependencies() {
        let baseRoot = makePackage(rootID, isRoot: true, deps: [pkgA])
        let baseA = makePackage(pkgA) // no deps
        let baseSnapshot = GraphSnapshot(
            packages: [rootID: baseRoot, pkgA: baseA],
            rootIdentity: rootID,
            findings: [], gitRef: nil, avieVersion: "1.0"
        )

        let headRoot = makePackage(rootID, isRoot: true, deps: [pkgA])
        let headA = makePackage(pkgA, deps: [pkgC]) // now has a dep
        let headC = makePackage(pkgC)
        let headSnapshot = GraphSnapshot(
            packages: [rootID: headRoot, pkgA: headA, pkgC: headC],
            rootIdentity: rootID,
            findings: [], gitRef: nil, avieVersion: "1.0"
        )

        let diff = DiffEngine().diff(base: baseSnapshot, head: headSnapshot)
        XCTAssertTrue(diff.addedPackages.contains(where: { $0.id == pkgC }))
        XCTAssertEqual(diff.packageCountDelta, 1)
        // package-c is transitive, so it's not in newDirectDependencies
        XCTAssertTrue(diff.newDirectDependencies.isEmpty)
    }

    func testDiffDetectsVersionChange() {
        let root = makePackage(rootID, isRoot: true, deps: [pkgA])
        let baseSnapshot = GraphSnapshot(
            packages: [rootID: root, pkgA: makePackage(pkgA, v: "1.0.0")],
            rootIdentity: rootID, findings: [], gitRef: nil, avieVersion: "1.0"
        )
        let headSnapshot = GraphSnapshot(
            packages: [rootID: root, pkgA: makePackage(pkgA, v: "2.0.0")],
            rootIdentity: rootID, findings: [], gitRef: nil, avieVersion: "1.0"
        )

        let diff = DiffEngine().diff(base: baseSnapshot, head: headSnapshot)
        XCTAssertEqual(diff.versionChanges.count, 1)
        XCTAssertEqual(diff.versionChanges.first?.package, pkgA)
        XCTAssertEqual(diff.versionChanges.first?.fromVersion, "1.0.0")
        XCTAssertEqual(diff.versionChanges.first?.toVersion, "2.0.0")
        XCTAssertTrue(diff.versionChanges.first?.isUpgrade == true)
    }

    func testDiffDetectsNewBinaryTarget() {
        let root = makePackage(rootID, isRoot: true, deps: [pkgA])
        let baseA = makePackage(pkgA, isBinary: false)
        let baseSnapshot = GraphSnapshot(
            packages: [rootID: root, pkgA: baseA],
            rootIdentity: rootID, findings: [], gitRef: nil, avieVersion: "1.0"
        )

        let headA = makePackage(pkgA, isBinary: true)
        let headSnapshot = GraphSnapshot(
            packages: [rootID: root, pkgA: headA],
            rootIdentity: rootID, findings: [], gitRef: nil, avieVersion: "1.0"
        )

        let diff = DiffEngine().diff(base: baseSnapshot, head: headSnapshot)
        XCTAssertTrue(diff.newBinaryTargets.contains(where: { $0.id == pkgA }))
        XCTAssertTrue(diff.hasBlockingIssues)
    }

    func testDiffExitsNonZeroOnBlockingIssues() {
        let root = makePackage(rootID, isRoot: true, deps: [])
        let baseSnapshot = GraphSnapshot(
            packages: [rootID: root],
            rootIdentity: rootID, findings: [], gitRef: nil, avieVersion: "1.0"
        )

        let finding = Finding(ruleID: .unreachablePin, severity: .error, confidence: .proven, summary: "Error", detail: "Error detail", graphPath: [], suggestedAction: "Fix", affectedPackage: pkgA)
        let headSnapshot = GraphSnapshot(
            packages: [rootID: root],
            rootIdentity: rootID, findings: [finding], gitRef: nil, avieVersion: "1.0"
        )

        let diff = DiffEngine().diff(base: baseSnapshot, head: headSnapshot)
        XCTAssertTrue(diff.hasBlockingIssues)
    }

    func testDiffReportsResolvedFindings() {
        let root = makePackage(rootID, isRoot: true, deps: [])
        let finding = Finding(ruleID: .unreachablePin, severity: .error, confidence: .proven, summary: "Stale", detail: "Stale", graphPath: [], suggestedAction: "Fix", affectedPackage: pkgA)

        let baseSnapshot = GraphSnapshot(
            packages: [rootID: root],
            rootIdentity: rootID, findings: [finding], gitRef: nil, avieVersion: "1.0"
        )

        let headSnapshot = GraphSnapshot(
            packages: [rootID: root],
            rootIdentity: rootID, findings: [], gitRef: nil, avieVersion: "1.0"
        )

        let diff = DiffEngine().diff(base: baseSnapshot, head: headSnapshot)
        XCTAssertEqual(diff.resolvedFindings.count, 1)
        XCTAssertEqual(diff.resolvedFindings.first?.affectedPackage, pkgA)
        XCTAssertTrue(diff.newFindings.isEmpty)
    }

    func testSARIFDiffPassesSchemaValidation() throws {
        let root = makePackage(rootID, isRoot: true, deps: [])
        let baseSnapshot = GraphSnapshot(
            packages: [rootID: root],
            rootIdentity: rootID, findings: [], gitRef: nil, avieVersion: "1.0"
        )

        let f1 = Finding(ruleID: .unreachablePin, severity: .error, confidence: .proven, summary: "Error 1", detail: "D1", graphPath: [], suggestedAction: "Fix", affectedPackage: pkgA)
        let f2 = Finding(ruleID: .testLeakage, severity: .warning, confidence: .proven, summary: "Warn 2", detail: "D2", graphPath: [], suggestedAction: "Fix", affectedPackage: pkgB)

        let headSnapshot = GraphSnapshot(
            packages: [rootID: root],
            rootIdentity: rootID, findings: [f1, f2], gitRef: nil, avieVersion: "1.0"
        )

        let diff = DiffEngine().diff(base: baseSnapshot, head: headSnapshot)
        
        let formatter = SARIFFormatter()
        let result = try formatter.format(diff)
        
        let data = result.data(using: .utf8)!
        let jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertEqual(jsonDict?["version"] as? String, "2.1.0")
        
        let runs = jsonDict?["runs"] as? [[String: Any]]
        XCTAssertEqual(runs?.count, 1)
        
        let tool = runs?.first?["tool"] as? [String: Any]
        let driver = tool?["driver"] as? [String: Any]
        XCTAssertEqual(driver?["name"] as? String, "Avie")
        
        let results = runs?.first?["results"] as? [[String: Any]]
        XCTAssertEqual(results?.count, 2)
    }

    func testSnapshotDiffPipelineEndToEnd() throws {
        // Simulates: avie snapshot (base) → add dep → avie snapshot (head) → avie diff
        // Validates the full data flow: GraphSnapshot → DiffEngine → DiffResult

        let swiftAlgorithms = PackageIdentity("swift-algorithms")
        let heavyFramework = PackageIdentity("heavy-framework")

        // Build base snapshot
        let baseRoot = makePackage(rootID, isRoot: true, deps: [swiftAlgorithms])
        let baseAlgorithms = makePackage(swiftAlgorithms)
        let baseSnapshot = GraphSnapshot(
            packages: [rootID: baseRoot, swiftAlgorithms: baseAlgorithms],
            rootIdentity: rootID,
            findings: [], gitRef: nil, avieVersion: "1.0"
        )

        // Build head snapshot
        let headRoot = makePackage(rootID, isRoot: true, deps: [swiftAlgorithms, heavyFramework])
        
        var headPackages: [PackageIdentity: ResolvedPackage] = [
            rootID: headRoot,
            swiftAlgorithms: baseAlgorithms
        ]
        
        var heavyDeps: [PackageIdentity] = []
        for i in 1...12 {
            let transitiveID = PackageIdentity("transitive-\(i)")
            heavyDeps.append(transitiveID)
            headPackages[transitiveID] = makePackage(transitiveID)
        }
        
        headPackages[heavyFramework] = makePackage(heavyFramework, deps: heavyDeps)
        
        let finding = Finding(
            ruleID: .excessiveFanout,
            severity: .warning,
            confidence: .proven,
            summary: "heavy-framework pulls in 12 transitive dependencies",
            detail: "This exceeds the configured threshold.",
            graphPath: [rootID, heavyFramework],
            suggestedAction: "Evaluate if this dependency is worth the weight.",
            affectedPackage: heavyFramework
        )
        
        let headSnapshot = GraphSnapshot(
            packages: headPackages,
            rootIdentity: rootID,
            findings: [finding],
            gitRef: nil, avieVersion: "1.0"
        )

        let diff = DiffEngine().diff(base: baseSnapshot, head: headSnapshot)

        // Asserts
        XCTAssertTrue(diff.addedPackages.contains(where: { $0.id == heavyFramework }))
        XCTAssertEqual(diff.newFindings.count, 1)
        XCTAssertEqual(diff.newFindings.first?.ruleID, .excessiveFanout)
        XCTAssertEqual(diff.newFindings.first?.affectedPackage, heavyFramework)
        XCTAssertEqual(diff.packageCountDelta, 13) // heavy-framework + 12 transitives
        XCTAssertFalse(diff.hasBlockingIssues)
        XCTAssertTrue(diff.resolvedFindings.isEmpty)
    }
}
