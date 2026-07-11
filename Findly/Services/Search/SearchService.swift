import Foundation
import SwiftData

/// Two-phase search over the local SwiftData store.
///
/// **Phase 1 — SQL predicate:** Filters by text across title and description
/// using `localizedStandardContains`, which maps to `CONTAINS[cd]` in SQLite.
///
/// **Phase 2 — In-memory tag filter:** If a root tag is supplied, collects all
/// descendant tag IDs via BFS and post-filters Phase 1 results in memory.
struct SearchService {

    // MARK: - Search

    /// Returns items matching `query` and/or belonging to descendants of `tagFilter`.
    ///
    /// - Parameters:
    ///   - query: Free-text query (empty string returns all items).
    ///   - tagFilter: Optionally restrict results to items tagged with this tag or any descendant.
    ///   - sortOrder: Determines result ordering.
    ///   - context: The `ModelContext` to query against.
    static func search(
        query: String,
        tagFilter: Tag? = nil,
        fileTypeFilter: Set<FileType>? = nil,
        dateRange: ClosedRange<Date>? = nil,
        sortOrder: SortOrder = .modifiedAt,
        context: ModelContext
    ) throws -> [Item] {

        let q = query.trimmingCharacters(in: .whitespaces)

        // Fetch all items sorted — personal vault corpus is small enough for in-memory filtering.
        // This lets us match against tag names, which SwiftData #Predicate cannot traverse in SQL.
        let allItems = try context.fetch(FetchDescriptor<Item>(sortBy: sortOrder.sortDescriptors))

        // Phase 1: filter by title, description, or tag hierarchy
        var results: [Item]
        if q.isEmpty {
            results = allItems
        } else {
            // Expand any tags whose names match the query to include all their descendants.
            // e.g. searching "nature" should find files tagged "mountain" (child of nature).
            let allTags = try context.fetch(FetchDescriptor<Tag>())
            let matchingTags = allTags.filter { $0.name.localizedStandardContains(q) }
            var expandedTagIDs = Set<UUID>()
            for tag in matchingTags {
                expandedTagIDs.formUnion(TagGraphTraverser.allDescendantIDs(of: tag))
            }

            results = allItems.filter { item in
                item.title.localizedStandardContains(q) ||
                item.itemDescription.localizedStandardContains(q) ||
                (!expandedTagIDs.isEmpty && item.tags.contains { expandedTagIDs.contains($0.id) })
            }
        }

        // Phase 2: tag hierarchy filter (in-memory BFS)
        if let root = tagFilter {
            let descendantIDs = TagGraphTraverser.allDescendantIDs(of: root)
            results = results.filter { item in
                item.tags.contains { descendantIDs.contains($0.id) }
            }
        }

        // Phase 3: file type filter
        if let types = fileTypeFilter, !types.isEmpty {
            results = results.filter { types.contains($0.fileType) }
        }

        // Phase 4: date range filter (by createdAt)
        if let range = dateRange {
            results = results.filter { range.contains($0.createdAt) }
        }

        return results
    }

    // MARK: - Recent items

    static func recentItems(limit: Int = 20, context: ModelContext) throws -> [Item] {
        var descriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
        )
        descriptor.predicate = #Predicate<Item> { $0.lastOpenedAt != nil }
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    // MARK: - Frequent items

    static func frequentItems(limit: Int = 10, context: ModelContext) throws -> [Item] {
        var descriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.viewCount, order: .reverse)]
        )
        descriptor.predicate = #Predicate<Item> { $0.viewCount > 0 }
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    // MARK: - Recently added

    static func recentlyAddedItems(limit: Int = 20, context: ModelContext) throws -> [Item] {
        var descriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    // MARK: - Favorites

    static func favoriteItems(context: ModelContext) throws -> [Item] {
        try context.fetch(FetchDescriptor<Item>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        ))
    }

    // MARK: - Stats

    static func totalItemCount(context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Item>())
    }

    static func totalTagCount(context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Tag>())
    }

    static func itemsByFileType(context: ModelContext) throws -> [FileType: Int] {
        let all = try context.fetch(FetchDescriptor<Item>())
        return Dictionary(grouping: all, by: \.fileType).mapValues(\.count)
    }
}

// MARK: - Sort order

extension SearchService {
    enum SortOrder {
        case modifiedAt
        case createdAt
        case title
        case viewCount
        case fileSize

        var sortDescriptors: [SortDescriptor<Item>] {
            switch self {
            case .modifiedAt: return [SortDescriptor(\.modifiedAt, order: .reverse)]
            case .createdAt:  return [SortDescriptor(\.createdAt,  order: .reverse)]
            case .title:      return [SortDescriptor(\.title,      order: .forward)]
            case .viewCount:  return [SortDescriptor(\.viewCount,  order: .reverse)]
            case .fileSize:   return [SortDescriptor(\.fileSize,   order: .reverse)]
            }
        }
    }
}
