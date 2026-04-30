import XCTest
@testable import AvieGraph
@testable import AvieCore

final class AvieGraphTests: XCTestCase {

    private func makeGraph() throws -> DependencyGraph {
        // A -> B -> D
        // A -> C -> D
        // A -> C -> E
        let packages: [PackageIdentity: ResolvedPackage] = [
            PackageIdentity("a"): ResolvedPackage(
                id: PackageIdentity("a"), url: "", version: "1.0.0", name: "A",
                directDependencies: [PackageIdentity("b"), PackageIdentity("c")],
                isRoot: true
            ),
            PackageIdentity("b"): ResolvedPackage(
                id: PackageIdentity("b"), url: "", version: "1.0.0", name: "B",
                directDependencies: [PackageIdentity("d")]
            ),
            PackageIdentity("c"): ResolvedPackage(
                id: PackageIdentity("c"), url: "", version: "1.0.0", name: "C",
                directDependencies: [PackageIdentity("d"), PackageIdentity("e")]
            ),
            PackageIdentity("d"): ResolvedPackage(
                id: PackageIdentity("d"), url: "", version: "1.0.0", name: "D",
                directDependencies: []
            ),
            PackageIdentity("e"): ResolvedPackage(
                id: PackageIdentity("e"), url: "", version: "1.0.0", name: "E",
                directDependencies: []
            ),
        ]
        return try DependencyGraph(packages: packages)
    }

    private func makeGraphWithUnreachable() throws -> DependencyGraph {
        // A -> B
        // F is unreachable
        let packages: [PackageIdentity: ResolvedPackage] = [
            PackageIdentity("a"): ResolvedPackage(
                id: PackageIdentity("a"), url: "", version: "1.0.0", name: "A",
                directDependencies: [PackageIdentity("b")],
                isRoot: true
            ),
            PackageIdentity("b"): ResolvedPackage(
                id: PackageIdentity("b"), url: "", version: "1.0.0", name: "B",
                directDependencies: []
            ),
            PackageIdentity("f"): ResolvedPackage(
                id: PackageIdentity("f"), url: "", version: "1.0.0", name: "F",
                directDependencies: []
            ),
        ]
        return try DependencyGraph(packages: packages)
    }

    func testBFSReachabilityIsCorrect() throws {
        let graph = try makeGraph()
        let traversal = GraphTraversal(graph: graph)
        let reachable = traversal.reachablePackages(from: graph.rootIdentity)

        XCTAssertEqual(reachable.count, 5)
        XCTAssertTrue(reachable.contains(PackageIdentity("a")))
        XCTAssertTrue(reachable.contains(PackageIdentity("b")))
        XCTAssertTrue(reachable.contains(PackageIdentity("c")))
        XCTAssertTrue(reachable.contains(PackageIdentity("d")))
        XCTAssertTrue(reachable.contains(PackageIdentity("e")))
    }

    func testBFSDetectsUnreachableNode() throws {
        let graph = try makeGraphWithUnreachable()
        let traversal = GraphTraversal(graph: graph)
        let reachable = traversal.reachablePackages(from: graph.rootIdentity)

        XCTAssertEqual(reachable.count, 2)
        XCTAssertTrue(reachable.contains(PackageIdentity("a")))
        XCTAssertTrue(reachable.contains(PackageIdentity("b")))
        XCTAssertFalse(reachable.contains(PackageIdentity("f")))
    }

    func testShortestPathFindsMinimalPath() throws {
        let graph = try makeGraph()
        let traversal = GraphTraversal(graph: graph)

        let path = traversal.shortestPath(from: PackageIdentity("a"), to: PackageIdentity("d"))
        XCTAssertNotNil(path)
        // A -> B -> D or A -> C -> D, both length 3
        XCTAssertEqual(path!.count, 3)
        XCTAssertEqual(path!.first, PackageIdentity("a"))
        XCTAssertEqual(path!.last, PackageIdentity("d"))
    }

    func testShortestPathReturnsNilForUnreachable() throws {
        let graph = try makeGraphWithUnreachable()
        let traversal = GraphTraversal(graph: graph)

        let path = traversal.shortestPath(from: PackageIdentity("a"), to: PackageIdentity("f"))
        XCTAssertNil(path)
    }

    func testShortestPathToSelf() throws {
        let graph = try makeGraph()
        let traversal = GraphTraversal(graph: graph)

        let path = traversal.shortestPath(from: PackageIdentity("a"), to: PackageIdentity("a"))
        XCTAssertEqual(path, [PackageIdentity("a")])
    }

    func testFindPathsFindsAllRoutes() throws {
        let graph = try makeGraph()
        let traversal = GraphTraversal(graph: graph)

        let paths = traversal.findPaths(from: PackageIdentity("a"), to: PackageIdentity("d"))
        // A -> B -> D and A -> C -> D
        XCTAssertEqual(paths.count, 2)

        let pathStrings = paths.map { $0.map(\.value).joined(separator: "->") }
        XCTAssertTrue(pathStrings.contains("a->b->d"))
        XCTAssertTrue(pathStrings.contains("a->c->d"))
    }

    func testMaximumDepth() throws {
        let graph = try makeGraph()
        let traversal = GraphTraversal(graph: graph)

        let depth = traversal.maximumDepth(from: PackageIdentity("a"))
        XCTAssertEqual(depth, 2) // A -> C -> E (2 edges)
    }

    func testTransitiveDependenciesExcludesSelf() throws {
        let graph = try makeGraph()
        let traversal = GraphTraversal(graph: graph)

        let transitive = traversal.allTransitiveDependencies(of: PackageIdentity("a"))
        XCTAssertEqual(transitive.count, 4)
        XCTAssertFalse(transitive.contains(PackageIdentity("a")))
    }
}
