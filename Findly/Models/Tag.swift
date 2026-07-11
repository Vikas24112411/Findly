import Foundation
import SwiftData

/// A tag node in the knowledge graph (DAG).
///
/// Tags support multiple parents (making the structure a Directed Acyclic Graph
/// rather than a plain tree). SwiftData persists the `parents`/`children` relationship
/// pair as a self-referential many-to-many join table.
///
/// - Important: Application code is responsible for preventing cycles before adding
///   edges. Use `TagGraphTraverser.wouldCreateCycle(adding:to:)` before mutating
///   `parents` or `children`.
@Model
final class Tag {

    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    var name: String

    /// Hex color string, e.g. `"#4A90E2"`.
    var colorHex: String

    /// SF Symbol name for the tag icon.
    var sfSymbol: String

    var createdAt: Date

    // MARK: - DAG edges (self-referential many-to-many)
    //
    // SwiftData creates a single join table for this self-referential M:M.
    // The `inverse:` on `parents` tells SwiftData that `children` is the
    // other side of the same relationship edge set.
    //
    // Fallback: If this causes schema migration issues in your Xcode version,
    // replace with an explicit `TagEdge` @Model (fromTag + toTag) and update
    // TagGraphTraverser accordingly.

    @Relationship(deleteRule: .nullify, inverse: \Tag.children)
    var parents: [Tag]

    @Relationship(deleteRule: .nullify)
    var children: [Tag]

    // MARK: - Associated items (inverse declared here so Item.tags can specify it)

    var items: [Item]

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#4A90E2",
        sfSymbol: String = "tag.fill"
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sfSymbol = sfSymbol
        self.createdAt = Date()
        self.parents = []
        self.children = []
        self.items = []
    }

    // MARK: - Helpers

    var isRoot: Bool     { parents.isEmpty }
    var isLeaf: Bool     { children.isEmpty }
    var itemCount: Int   { items.count }

    /// Total number of items under this tag, including all descendants.
    /// This is a recursive count — use sparingly on large graphs.
    var totalItemCount: Int {
        var visited = Set<UUID>()
        return countItems(visited: &visited)
    }

    private func countItems(visited: inout Set<UUID>) -> Int {
        guard visited.insert(id).inserted else { return 0 }
        return items.count + children.reduce(0) { $0 + $1.countItems(visited: &visited) }
    }
}
