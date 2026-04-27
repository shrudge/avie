import AvieCore

public struct GraphTraversal {
    public let graph: DependencyGraph

    public init(graph: DependencyGraph) {
        self.graph = graph
    }

    public func reachablePackages(from start: PackageIdentity) -> Set<PackageIdentity> {
        var visited = Set<PackageIdentity>()
        var queue = [start]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard !visited.contains(current) else { continue }
            visited.insert(current)

            let neighbors = graph.adjacency[current] ?? []
            queue.append(contentsOf: neighbors.filter { !visited.contains($0) })
        }

        return visited
    }

    public func shortestPath(
        from start: PackageIdentity,
        to target: PackageIdentity
    ) -> [PackageIdentity]? {
        if start == target { return [start] }

        var visited = Set<PackageIdentity>()
        var queue: [[PackageIdentity]] = [[start]]

        while !queue.isEmpty {
            let path = queue.removeFirst()
            let current = path.last!

            guard !visited.contains(current) else { continue }
            visited.insert(current)

            for neighbor in graph.adjacency[current] ?? [] {
                let newPath = path + [neighbor]
                if neighbor == target { return newPath }
                queue.append(newPath)
            }
        }

        return nil
    }

    public func allTransitiveDependencies(
        of packageID: PackageIdentity
    ) -> Set<PackageIdentity> {
        var result = reachablePackages(from: packageID)
        result.remove(packageID)
        return result
    }

    public func maximumDepth(from start: PackageIdentity) -> Int {
        func dfs(_ node: PackageIdentity, _ visited: inout Set<PackageIdentity>) -> Int {
            if visited.contains(node) { return 0 }
            visited.insert(node)
            let childDepths = (graph.adjacency[node] ?? []).map { child -> Int in
                var v = visited
                return 1 + dfs(child, &v)
            }
            return childDepths.max() ?? 0
        }
        var visited = Set<PackageIdentity>()
        return dfs(start, &visited)
    }

    /// Bug 8 fix: sort initial queue by PackageIdentity.value (String) for deterministic output.
    /// The previous sort used $0.value < $1.value on the dict tuple where value was Int (in-degree),
    /// but all entries at this point have value == 0 — making it a no-op that produced random order.
    public func topologicalSort() -> [PackageIdentity] {
        var inDegree: [PackageIdentity: Int] = [:]
        for id in graph.packages.keys { inDegree[id] = 0 }

        for (_, deps) in graph.adjacency {
            for dep in deps {
                inDegree[dep, default: 0] += 1
            }
        }

        var queue = inDegree.filter { $0.value == 0 }.map { $0.key }.sorted(by: { $0.value < $1.value })
        var result: [PackageIdentity] = []
        var head = 0 
        
        while head < queue.count {
            let node = queue[head]
            head += 1
            result.append(node)
            
            var newlyUnlocked: [PackageIdentity] = []
            for neighbor in graph.adjacency[node] ?? [] {
                inDegree[neighbor]! -= 1
                if inDegree[neighbor]! == 0 {
                    newlyUnlocked.append(neighbor)
                }
            }
            newlyUnlocked.sort(by: { $0.value < $1.value })
            queue.append(contentsOf: newlyUnlocked)
        }
        return result
    }

    public func allPaths(
        from start: PackageIdentity,
        to target: PackageIdentity,
        maxPaths: Int = 10
    ) -> [[PackageIdentity]] {
        var results: [[PackageIdentity]] = []
        var currentPath: [PackageIdentity] = [start]
        var visited = Set<PackageIdentity>()

        func dfs(_ node: PackageIdentity) {
            if results.count >= maxPaths { return }
            if node == target {
                results.append(currentPath)
                return
            }
            visited.insert(node)
            for neighbor in graph.adjacency[node] ?? [] {
                if !visited.contains(neighbor) {
                    currentPath.append(neighbor)
                    dfs(neighbor)
                    currentPath.removeLast()
                }
            }
            visited.remove(node)
        }

        dfs(start)
        return results
    }
}
