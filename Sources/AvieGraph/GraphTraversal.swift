import Foundation
import AvieCore

public class GraphTraversal {
    public let graph: DependencyGraph
    private var reachableCache: [PackageIdentity: Set<PackageIdentity>] = [:]
    private let cacheLock = NSLock()

    public init(graph: DependencyGraph) {
        self.graph = graph
    }

    public func reachablePackages(from start: PackageIdentity) -> Set<PackageIdentity> {
        cacheLock.lock()
        if let cached = reachableCache[start] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        // Compute outside of lock to avoid blocking other threads
        var visited = Set<PackageIdentity>()
        var queue = [start]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard !visited.contains(current) else { continue }
            visited.insert(current)

            let neighbors = graph.adjacency[current] ?? []
            queue.append(contentsOf: neighbors.filter { !visited.contains($0) })
        }

        // Double-checked locking: check cache again in case another thread computed it
        cacheLock.lock()
        if let alreadyCached = reachableCache[start] {
            cacheLock.unlock()
            return alreadyCached
        }
        reachableCache[start] = visited
        cacheLock.unlock()
        
        return visited
    }

    public func shortestPath(
        from start: PackageIdentity,
        to target: PackageIdentity
    ) -> [PackageIdentity]? {
        if start == target { return [start] }

        var visited = Set<PackageIdentity>()
        var queue: [PackageIdentity] = [start]
        var parent: [PackageIdentity: PackageIdentity] = [:]
        visited.insert(start)

        while !queue.isEmpty {
            let current = queue.removeFirst()

            for neighbor in graph.adjacency[current] ?? [] {
                if !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    parent[neighbor] = current
                    queue.append(neighbor)
                    
                    if neighbor == target {
                        // Reconstruct path from target to start
                        var path = [target]
                        var currentNode = target
                        while let parentNode = parent[currentNode], parentNode != start {
                            path.append(parentNode)
                            currentNode = parentNode
                        }
                        path.append(start)
                        return path.reversed()
                    }
                }
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
        var visited = Set<PackageIdentity>()
        return dfs(start, visited: &visited)
    }
    
    private func dfs(_ node: PackageIdentity, visited: inout Set<PackageIdentity>) -> Int {
        if visited.contains(node) { return 0 }
        visited.insert(node)
        
        let neighbors = graph.adjacency[node] ?? []
        if neighbors.isEmpty {
            return 0 // Leaf node has depth 0
        }
        
        var maxChildDepth = 0
        for neighbor in neighbors {
            if !visited.contains(neighbor) {
                let childDepth = dfs(neighbor, visited: &visited)
                maxChildDepth = max(maxChildDepth, childDepth)
            }
        }
        
        return 1 + maxChildDepth
    }

    /// Bug 8 fix: sort initial queue by PackageIdentity.value (String) for deterministic output.
    /// The previous sort used $0.value < $1.value on the dict tuple where value was Int (in-degree),
    /// but all entries at this point have value == 0 — making it a no-op that produced random order.
    /// Now we sort by package identity string for consistent, deterministic topological ordering.
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

    /// Finds multiple paths from start to target, preferentially finding shorter paths first (BFS).
    /// - Parameters:
    ///   - start: Starting package identity
    ///   - target: Target package identity
    ///   - maxPaths: Maximum number of paths to return
    /// - Returns: An array of paths, where each path is an array of identities.
    public func findPaths(
        from start: PackageIdentity,
        to target: PackageIdentity,
        maxPaths: Int = 10
    ) -> [[PackageIdentity]] {
        var results: [[PackageIdentity]] = []
        
        // (currentNode, pathSoFar)
        var queue: [(PackageIdentity, [PackageIdentity])] = [(start, [start])]
        
        while !queue.isEmpty && results.count < maxPaths {
            let (current, path) = queue.removeFirst()
            
            if current == target {
                results.append(path)
                continue
            }
            
            for neighbor in graph.adjacency[current] ?? [] {
                // Avoid cycles in the current path
                if !path.contains(neighbor) {
                    var newPath = path
                    newPath.append(neighbor)
                    queue.append((neighbor, newPath))
                }
            }
        }
        
        return results
    }
}
