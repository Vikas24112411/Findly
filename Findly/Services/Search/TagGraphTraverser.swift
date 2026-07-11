import Foundation

/// Performs graph operations on the `Tag` DAG.
///
/// All methods are `nonisolated` and operate on snapshots of the tag graph
/// passed in as parameters — no shared mutable state.
struct TagGraphTraverser {

    // MARK: - Descendants (BFS)

    /// Returns all descendant tags, inclusive of `root` itself.
    /// Uses iterative BFS to avoid stack overflow on deep graphs.
    static func allDescendants(of root: Tag) -> Set<Tag> {
        var visited = Set<Tag>()
        var queue: [Tag] = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            queue.append(contentsOf: current.children)
        }
        return visited
    }

    /// Returns just the IDs of all descendants (including root).
    /// Useful for SwiftData in-memory post-filtering without keeping Tag references alive.
    static func allDescendantIDs(of root: Tag) -> Set<UUID> {
        Set(allDescendants(of: root).map(\.id))
    }

    // MARK: - Ancestors (BFS upward)

    /// Returns all ancestor tags, inclusive of `tag` itself.
    static func allAncestors(of tag: Tag) -> Set<Tag> {
        var visited = Set<Tag>()
        var queue: [Tag] = [tag]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            queue.append(contentsOf: current.parents)
        }
        return visited
    }

    // MARK: - Cycle detection

    /// Returns `true` if adding `candidateParent` as a parent of `child`
    /// would create a cycle in the DAG.
    ///
    /// Algorithm: walk DOWN from `child` via children. If we reach `candidateParent`,
    /// making it a parent of `child` would create a cycle.
    /// Uses `children` (not `parents`) because SwiftData's self-referential `parents`
    /// relationship can load unreliably across fetch cycles.
    static func wouldCreateCycle(adding candidateParent: Tag, to child: Tag) -> Bool {
        if candidateParent.id == child.id { return true }
        var visited = Set<UUID>()
        var queue: [Tag] = [child]
        while !queue.isEmpty {
            let node = queue.removeFirst()
            guard visited.insert(node.id).inserted else { continue }
            if node.id == candidateParent.id { return true }
            queue.append(contentsOf: node.children)
        }
        return false
    }

    // MARK: - Roots

    /// Returns all tags that have no parents (top-level nodes).
    ///
    /// Computed from the `children` side of the relationship rather than
    /// `tag.parents.isEmpty`, because SwiftData's self-referential `parents`
    /// array can appear empty after a fetch even when relationships exist.
    static func rootTags(from allTags: [Tag]) -> [Tag] {
        let childIDs = Set(allTags.flatMap { $0.children.map(\.id) })
        return allTags.filter { !childIDs.contains($0.id) }.sorted { $0.name < $1.name }
    }

    // MARK: - Path

    /// Returns one possible path from a root tag down to `tag`, e.g.
    /// `["Living Things", "Animals", "Mammals", "Lion"]`.
    static func pathFromRoot(to tag: Tag) -> [Tag] {
        // BFS upward to find a root, then reverse the path.
        var path: [Tag] = []
        var current: Tag? = tag
        var visited = Set<UUID>()
        while let node = current {
            guard visited.insert(node.id).inserted else { break }
            path.append(node)
            current = node.parents.first
        }
        return path.reversed()
    }
}

// MARK: - Tag: Hashable conformance for Set usage

extension Tag: Hashable {
    static func == (lhs: Tag, rhs: Tag) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
