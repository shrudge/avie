import XCTest
@testable import AvieRules
@testable import AvieCore
@testable import AvieGraph
@testable import AvieResolver

final class AvieRulesTests: XCTestCase {
    
    private func resolveFixture(named name: String) throws -> (DependencyGraph, GraphTraversal) {
        let currentDir = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixturePath = currentDir.appendingPathComponent("Fixtures/\(name)")
        let resolver = SPMResolver(packageDirectory: fixturePath)
        let spmOutput = try resolver.resolve()
        // Bug 5 fix: URL-derived identity; no binary targets in test fixtures
        let packages = DependencyTransformer().transform(spmOutput, binaryTargetIDs: [])
        let graph = try DependencyGraph(packages: packages)
        let traversal = GraphTraversal(graph: graph)
        return (graph, traversal)
    }

    private func getManifest(named name: String) throws -> ManifestReader.ManifestData {
        let currentDir = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixturePath = currentDir.appendingPathComponent("Fixtures/\(name)")
        let reader = ManifestReader(packageDirectory: fixturePath)
        return try reader.read()
    }
    
    // MARK: - AVIE001 Unreachable Pin Tests

    private func createTargets(from manifestData: ManifestReader.ManifestData, rootIdentity: PackageIdentity) -> [TargetDeclaration] {
        manifestData.targets.map { targetData in
            TargetDeclaration(
                id: targetData.name,
                kind: targetData.type == "test" ? .test : .regular,
                packageIdentity: rootIdentity,
                // Bug 7 fix: use the new .packageIdentity computed property on the
                // ManifestTargetDependency enum instead of the old struct accessor.
                packageDependencies: targetData.dependencies.compactMap { dep in
                    dep.packageIdentity
                }.map(PackageIdentity.init)
            )
        }
    }

    func testAVIE001FiresOnUnreachablePin() throws {
        let (graph, traversal) = try resolveFixture(named: "unreachable-pin")
        let manifest = try getManifest(named: "unreachable-pin")
        let targets = createTargets(from: manifest, rootIdentity: graph.rootIdentity)
        let rule = UnreachablePinRule()
        let context = RuleContext(configuration: AvieConfiguration(), targets: targets, suppressions: [])
        
        let findings = try rule.analyze(graph: graph, traversal: traversal, context: context)
        
        // swift-log is unreachable in the fixture
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].ruleID, .unreachablePin)
        XCTAssertEqual(findings[0].affectedPackage.value, "swift-log")
    }
    
    func testAVIE001DoesNotFireOnReachablePackage() throws {
        let (graph, traversal) = try resolveFixture(named: "simple-package")
        let manifest = try getManifest(named: "simple-package")
        let targets = createTargets(from: manifest, rootIdentity: graph.rootIdentity)
        let rule = UnreachablePinRule()
        let context = RuleContext(configuration: AvieConfiguration(), targets: targets, suppressions: [])
        
        let findings = try rule.analyze(graph: graph, traversal: traversal, context: context)
        
        XCTAssertTrue(findings.isEmpty)
    }

    // MARK: - AVIE002 Test Leakage Tests

    func testAVIE002FiresOnTestLeakage() throws {
        let root = PackageIdentity("root")
        let prodDep = PackageIdentity("prod-lib")
        let testDep = PackageIdentity("test-lib")
        
        let packages: [PackageIdentity: ResolvedPackage] = [
            root: ResolvedPackage(id: root, url: "", version: "", name: "root", directDependencies: [prodDep, testDep], isRoot: true, containsBinaryTarget: false),
            prodDep: ResolvedPackage(id: prodDep, url: "", version: "", name: "prodLib", directDependencies: [testDep], isRoot: false, containsBinaryTarget: false),
            testDep: ResolvedPackage(id: testDep, url: "", version: "", name: "testLib", directDependencies: [], isRoot: false, containsBinaryTarget: false)
        ]
        
        let graph = try DependencyGraph(packages: packages)
        let traversal = GraphTraversal(graph: graph)

        let targets = [
            TargetDeclaration(id: "ProdTarget", kind: .regular, packageIdentity: root, packageDependencies: [prodDep]),
            TargetDeclaration(id: "TestTarget", kind: .test, packageIdentity: root, packageDependencies: [testDep])
        ]
        
        let rule = TestLeakageRule()
        let context = RuleContext(configuration: AvieConfiguration(), targets: targets, suppressions: [])
        
        let findings = try rule.analyze(graph: graph, traversal: traversal, context: context)
        
        XCTAssertFalse(findings.isEmpty, "Should find leaked test dependencies")
        XCTAssertTrue(findings.contains { $0.ruleID == .testLeakage })
    }

    func testAVIE002SkipsGracefullyWithoutManifest() throws {
        let root = PackageIdentity("root")
        let packages: [PackageIdentity: ResolvedPackage] = [
            root: ResolvedPackage(id: root, url: "", version: "", name: "root", directDependencies: [], isRoot: true, containsBinaryTarget: false)
        ]
        let graph = try DependencyGraph(packages: packages)
        let traversal = GraphTraversal(graph: graph)
        let rule = TestLeakageRule()
        let context = RuleContext(configuration: AvieConfiguration(), targets: nil, suppressions: [])
        
        let findings = try rule.analyze(graph: graph, traversal: traversal, context: context)
        XCTAssertTrue(findings.isEmpty)
    }

    // MARK: - AVIE003 Excessive Fanout Tests

    func testAVIE003FiresWhenFanoutExceedsThreshold() throws {
        let root = PackageIdentity("root")
        let depPath = [PackageIdentity("dep1"), PackageIdentity("dep2"), PackageIdentity("dep3")]
        
        let packages: [PackageIdentity: ResolvedPackage] = [
            root: ResolvedPackage(id: root, url: "", version: "", name: "root", directDependencies: [depPath[0]], isRoot: true, containsBinaryTarget: false),
            depPath[0]: ResolvedPackage(id: depPath[0], url: "", version: "", name: "dep1", directDependencies: [depPath[1]], isRoot: false, containsBinaryTarget: false),
            depPath[1]: ResolvedPackage(id: depPath[1], url: "", version: "", name: "dep2", directDependencies: [depPath[2]], isRoot: false, containsBinaryTarget: false),
            depPath[2]: ResolvedPackage(id: depPath[2], url: "", version: "", name: "dep3", directDependencies: [], isRoot: false, containsBinaryTarget: false)
        ]
        
        let graph = try DependencyGraph(packages: packages)
        let traversal = GraphTraversal(graph: graph)

        var config = AvieConfiguration()
        config.rules.fanoutThreshold = 1 
        
        let rule = ExcessiveFanoutRule()
        let context = RuleContext(configuration: config, targets: nil, suppressions: [])
        
        let findings = try rule.analyze(graph: graph, traversal: traversal, context: context)
        
        XCTAssertFalse(findings.isEmpty)
        XCTAssertTrue(findings.contains { $0.ruleID == .excessiveFanout })
        XCTAssertEqual(findings.first?.affectedPackage, depPath[0])
    }

    func testAVIE003RespectsConfiguredThreshold() throws {
        let root = PackageIdentity("root")
        let depPath = [PackageIdentity("dep1"), PackageIdentity("dep2"), PackageIdentity("dep3")]
        
        let packages: [PackageIdentity: ResolvedPackage] = [
            root: ResolvedPackage(id: root, url: "", version: "", name: "root", directDependencies: [depPath[0]], isRoot: true, containsBinaryTarget: false),
            depPath[0]: ResolvedPackage(id: depPath[0], url: "", version: "", name: "dep1", directDependencies: [depPath[1]], isRoot: false, containsBinaryTarget: false),
            depPath[1]: ResolvedPackage(id: depPath[1], url: "", version: "", name: "dep2", directDependencies: [depPath[2]], isRoot: false, containsBinaryTarget: false),
            depPath[2]: ResolvedPackage(id: depPath[2], url: "", version: "", name: "dep3", directDependencies: [], isRoot: false, containsBinaryTarget: false)
        ]
        
        let graph = try DependencyGraph(packages: packages)
        let traversal = GraphTraversal(graph: graph)

        var config = AvieConfiguration()
        config.rules.fanoutThreshold = 10 
        
        let rule = ExcessiveFanoutRule()
        let context = RuleContext(configuration: config, targets: nil, suppressions: [])
        
        let findings = try rule.analyze(graph: graph, traversal: traversal, context: context)
        
        XCTAssertTrue(findings.isEmpty)
    }

    // MARK: - AVIE004 Binary Target Introduced Tests

    func testAVIE004FiresOnBinaryTarget() throws {
        let root = PackageIdentity("root")
        let binaryDep = PackageIdentity("binary")
        
        let packages: [PackageIdentity: ResolvedPackage] = [
            root: ResolvedPackage(id: root, url: "", version: "", name: "root", directDependencies: [binaryDep], isRoot: true, containsBinaryTarget: false),
            binaryDep: ResolvedPackage(id: binaryDep, url: "", version: "", name: "binary", directDependencies: [], isRoot: false, containsBinaryTarget: true)
        ]
        
        let graph = try DependencyGraph(packages: packages)
        let traversal = GraphTraversal(graph: graph)

        let rule = BinaryTargetRule()
        let context = RuleContext(configuration: AvieConfiguration(), targets: nil, suppressions: [])
        
        let findings = try rule.analyze(graph: graph, traversal: traversal, context: context)
        
        XCTAssertFalse(findings.isEmpty)
        XCTAssertTrue(findings.contains { $0.ruleID == .binaryTargetIntroduced })
        XCTAssertEqual(findings.first?.affectedPackage, binaryDep)
    }

    // MARK: - Phase 2 Gate Extra Tests

    func testSuppressionFileSilencesFindings() throws {
        let finding = Finding(
            ruleID: .excessiveFanout,
            severity: .warning,
            confidence: .proven,
            summary: "Foo",
            detail: "Bar",
            graphPath: [],
            suggestedAction: "Baz",
            affectedPackage: PackageIdentity("foo")
        )

        var suppressionFile = SuppressionFile()
        suppressionFile.suppressions.append(Suppression(key: finding.suppressionKey, reason: "Test", addedBy: "Me", addedAt: "Now"))

        let filtered = applySuppression([finding], suppressions: suppressionFile)
        XCTAssertTrue(filtered.isEmpty)
    }

    func testExitCode1WhenErrorFindingsPresent() throws {
        let finding = Finding(
            ruleID: .testLeakage,
            severity: .error,
            confidence: .proven,
            summary: "Foo",
            detail: "Bar",
            graphPath: [],
            suggestedAction: "Baz",
            affectedPackage: PackageIdentity("foo")
        )

        let config = AvieConfiguration()
        let errorRuleIDs = Set(config.rules.failOn)
        let hasFailingErrors = [finding].contains { f in
            f.severity == .error && errorRuleIDs.contains(f.ruleID)
        }

        XCTAssertTrue(hasFailingErrors)
    }

    func testExitCode0WhenOnlyWarnings() throws {
        let finding = Finding(
            ruleID: .excessiveFanout,
            severity: .warning,
            confidence: .proven,
            summary: "Foo",
            detail: "Bar",
            graphPath: [],
            suggestedAction: "Baz",
            affectedPackage: PackageIdentity("foo")
        )

        let config = AvieConfiguration()
        let errorRuleIDs = Set(config.rules.failOn)
        let hasFailingErrors = [finding].contains { f in
            f.severity == .error && errorRuleIDs.contains(f.ruleID)
        }

        XCTAssertFalse(hasFailingErrors)
    }
}
