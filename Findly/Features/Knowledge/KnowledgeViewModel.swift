import Foundation
import SwiftData

@Observable
@MainActor
final class KnowledgeViewModel {

    // MARK: - State

    var rootTags: [Tag] = []
    var expandedTagIDs: Set<UUID> = []
    var selectedTag: Tag? = nil
    var tagItems: [Item] = []
    var searchText: String = ""

    // MARK: - Sheet state

    var showCreateTag: Bool = false
    var tagToRename: Tag? = nil
    var tagToCreateChildFor: Tag? = nil

    // MARK: - Context

    private var context: ModelContext?

    func setup(context: ModelContext) {
        self.context = context
        loadRootTags()
    }

    // MARK: - Load

    func loadRootTags() {
        guard let context else { return }
        let all = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        rootTags = TagGraphTraverser.rootTags(from: all)
    }

    var filteredRootTags: [Tag] {
        guard !searchText.isEmpty else { return rootTags }
        return rootTags.filter { tagMatches($0, query: searchText) }
    }

    private func tagMatches(_ tag: Tag, query: String) -> Bool {
        tag.name.localizedCaseInsensitiveContains(query) ||
        tag.children.contains { tagMatches($0, query: query) }
    }

    // MARK: - Search expand

    func expandMatchingTags(query: String) {
        guard !query.isEmpty else { return }
        for tag in rootTags {
            expandAncestorsOfDirectMatches(tag, query: query)
        }
    }

    /// Expands a tag only when a descendant directly matches the query but the tag itself does not.
    /// This reveals the path to the matching tag without expanding the match or anything below it.
    @discardableResult
    private func expandAncestorsOfDirectMatches(_ tag: Tag, query: String) -> Bool {
        let selfMatches = tag.name.localizedCaseInsensitiveContains(query)
        var anyDescendantMatches = false
        for child in tag.children {
            if expandAncestorsOfDirectMatches(child, query: query) {
                anyDescendantMatches = true
            }
        }
        if anyDescendantMatches && !selfMatches {
            expandedTagIDs.insert(tag.id)
        }
        return selfMatches || anyDescendantMatches
    }

    // MARK: - Expand / Collapse

    func toggleExpansion(of tag: Tag) {
        if expandedTagIDs.contains(tag.id) {
            expandedTagIDs.remove(tag.id)
        } else {
            expandedTagIDs.insert(tag.id)
        }
    }

    func isExpanded(_ tag: Tag) -> Bool {
        expandedTagIDs.contains(tag.id)
    }

    // MARK: - Select tag

    func selectTag(_ tag: Tag) {
        selectedTag = tag
        loadItemsForTag(tag)
    }

    func loadItemsForTag(_ tag: Tag) {
        guard let context else { return }
        let descendantIDs = TagGraphTraverser.allDescendantIDs(of: tag)
        let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        tagItems = all.filter { item in
            item.tags.contains { descendantIDs.contains($0.id) }
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - CRUD

    func createTag(name: String, colorHex: String, sfSymbol: String, parent: Tag? = nil) {
        guard let context else { return }
        let tag = Tag(name: name, colorHex: colorHex, sfSymbol: sfSymbol)
        context.insert(tag)
        if let parent {
            tag.parents.append(parent)
            parent.children.append(tag)
        }
        try? context.save()
        loadRootTags()
    }

    func renameTag(_ tag: Tag, to name: String) {
        tag.name = name
        try? context?.save()
        loadRootTags()
    }

    func deleteTag(_ tag: Tag) {
        context?.delete(tag)
        try? context?.save()
        loadRootTags()
    }

    func addParent(_ parent: Tag, to child: Tag) {
        guard let context else { return }
        guard !TagGraphTraverser.wouldCreateCycle(adding: parent, to: child) else { return }
        // Use `children` as the source of truth (more reliable than `parents` in SwiftData
        // self-referential relationships).
        if !parent.children.contains(where: { $0.id == child.id }) {
            parent.children.append(child)
            if !child.parents.contains(where: { $0.id == parent.id }) {
                child.parents.append(parent)
            }
            try? context.save()
            loadRootTags()
        }
    }

    /// Removes `tag` from all parents, making it a top-level root tag.
    func makeTopLevel(_ tag: Tag) {
        guard let context else { return }
        let all = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        // Find every tag that lists `tag` in its children and remove it.
        // We don't rely on tag.parents here for the same reliability reason.
        for other in all where other.children.contains(where: { $0.id == tag.id }) {
            other.children.removeAll { $0.id == tag.id }
        }
        tag.parents.removeAll()
        try? context.save()
        loadRootTags()
    }
}
