import XCTest
@testable import AvieResolver
@testable import AvieCore

final class AvieResolverTests: XCTestCase {

    func testResolverValidationRejectsXcodeProject() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("avie-test-xcode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let xcodeproj = tmpDir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)

        // Also need Package.swift so it doesn't fail on that first
        let manifest = tmpDir.appendingPathComponent("Package.swift")
        try "// swift-tools-version: 5.9".write(to: manifest, atomically: true, encoding: .utf8)

        let resolver = SPMResolver(packageDirectory: tmpDir)

        XCTAssertThrowsError(try resolver.validate()) { error in
            guard let resolverError = error as? SPMResolver.ResolverError else {
                XCTFail("Expected ResolverError")
                return
            }
            if case .xcodeProjectDetected = resolverError {
                // expected
            } else {
                XCTFail("Expected xcodeProjectDetected, got \(resolverError)")
            }
        }
    }

    func testResolverValidationRejectsUnresolvedPackage() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("avie-test-nomanifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let resolver = SPMResolver(packageDirectory: tmpDir)

        XCTAssertThrowsError(try resolver.validate()) { error in
            guard let resolverError = error as? SPMResolver.ResolverError else {
                XCTFail("Expected ResolverError")
                return
            }
            if case .packageManifestNotFound = resolverError {
                // expected: no Package.swift means package is not resolved
            } else {
                XCTFail("Expected packageManifestNotFound, got \(resolverError)")
            }
        }
    }

    func testDependencyTransformerPreservesEdges() {
        let root = SPMDependencyOutput(
            name: "MyApp",
            url: "file:///root/myapp",
            version: "unspecified",
            path: "/root",
            dependencies: [
                SPMDependencyOutput(
                    name: "LibA",
                    url: "https://github.com/test/lib-a",
                    version: "1.0.0",
                    path: "/deps/lib-a",
                    dependencies: [
                        SPMDependencyOutput(
                            name: "LibC",
                            url: "https://github.com/test/lib-c",
                            version: "2.0.0",
                            path: "/deps/lib-c",
                            dependencies: []
                        )
                    ]
                ),
                SPMDependencyOutput(
                    name: "LibB",
                    url: "https://github.com/test/lib-b",
                    version: "1.5.0",
                    path: "/deps/lib-b",
                    dependencies: []
                )
            ]
        )

        let transformer = DependencyTransformer()
        // Bug 5 fix: pass binaryTargetIDs (empty for this test)
        let packages = transformer.transform(root, binaryTargetIDs: [])

        XCTAssertEqual(packages.count, 4)

        // Bug 5 fix: identities are now URL-derived (last path component, lowercased)
        // "file:///root/myapp" → "myapp"
        // "https://github.com/test/lib-a" → "lib-a"
        let myApp = packages[PackageIdentity("myapp")]
        XCTAssertNotNil(myApp)
        XCTAssertTrue(myApp!.isRoot)
        XCTAssertEqual(myApp!.directDependencies.count, 2)

        let libA = packages[PackageIdentity("lib-a")]
        XCTAssertNotNil(libA)
        XCTAssertFalse(libA!.isRoot)
        XCTAssertEqual(libA!.directDependencies.count, 1)
        XCTAssertEqual(libA!.directDependencies[0], PackageIdentity("lib-c"))

        let libB = packages[PackageIdentity("lib-b")]
        XCTAssertNotNil(libB)
        XCTAssertEqual(libB!.directDependencies.count, 0)

        let libC = packages[PackageIdentity("lib-c")]
        XCTAssertNotNil(libC)
        XCTAssertEqual(libC!.directDependencies.count, 0)
    }
}
