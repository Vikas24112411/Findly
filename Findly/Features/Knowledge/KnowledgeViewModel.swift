import Foundation
import SwiftData

@Observable
@MainActor
final class KnowledgeViewModel {

    // MARK: - Browsing state

    private(set) var allTags: [Tag] = []
    private(set) var rootTags: [Tag] = []
    private(set) var matchingTagIDs: Set<UUID> = []
    private(set) var visibleTagIDs: Set<UUID> = []
    private(set) var tagItems: [Item] = []
    private(set) var errorMessage: String?

    var expandedTagIDs: Set<UUID> = []
    var searchText = ""

    private var expandedIDsBeforeSearch: Set<UUID>?
    private var context: ModelContext?

    // MARK: - Setup and loading

    func setup(context: ModelContext) {
        guard self.context !== context else {
            reload()
            return
        }

        self.context = context
        do {
            try normalizeLegacyMultipleParents()
            try loadTags()
        } catch {
            report(error, fallback: "Tags couldn’t be loaded.")
        }
    }

    func reload() {
        do {
            try loadTags()
        } catch {
            report(error, fallback: "Tags couldn’t be refreshed.")
        }
    }

    private func loadTags() throws {
        guard let context else { return }
        allTags = try context.fetch(FetchDescriptor<Tag>())
        rootTags = Self.sorted(TagGraphTraverser.rootTags(from: allTags))
        refreshSearchResults()
    }

    // MARK: - Search

    var filteredRootTags: [Tag] {
        guard !trimmedSearchText.isEmpty else { return rootTags }
        return rootTags.filter { visibleTagIDs.contains($0.id) }
    }

    var hasExactSearchMatch: Bool {
        let query = trimmedSearchText
        guard !query.isEmpty else { return false }
        return allTags.contains {
            $0.name.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setSearchText(_ value: String) {
        let wasSearching = !trimmedSearchText.isEmpty
        searchText = value
        let isSearching = !trimmedSearchText.isEmpty

        if !wasSearching && isSearching {
            expandedIDsBeforeSearch = expandedTagIDs
        } else if wasSearching && !isSearching {
            expandedTagIDs = expandedIDsBeforeSearch ?? expandedTagIDs
            expandedIDsBeforeSearch = nil
        }

        refreshSearchResults()
    }

    private func refreshSearchResults() {
        let query = trimmedSearchText
        guard !query.isEmpty else {
            matchingTagIDs = []
            visibleTagIDs = Set(allTags.map(\.id))
            return
        }

        let matches = allTags.filter { $0.name.localizedStandardContains(query) }
        matchingTagIDs = Set(matches.map(\.id))

        let incoming = incomingParents()
        var visible = matchingTagIDs
        var ancestorsToExpand = Set<UUID>()

        for match in matches {
            var currentID = match.id
            var visited = Set<UUID>()
            while let parent = incoming[currentID]?.first, visited.insert(parent.id).inserted {
                visible.insert(parent.id)
                ancestorsToExpand.insert(parent.id)
                currentID = parent.id
            }
        }

        visibleTagIDs = visible
        expandedTagIDs = (expandedIDsBeforeSearch ?? expandedTagIDs).union(ancestorsToExpand)
    }

    func visibleChildren(of tag: Tag) -> [Tag] {
        let children = Self.sorted(tag.children)
        guard !trimmedSearchText.isEmpty else { return children }
        return children.filter { visibleTagIDs.contains($0.id) }
    }

    // MARK: - Expansion

    func toggleExpansion(of tag: Tag) {
        if expandedTagIDs.contains(tag.id) {
            expandedTagIDs.remove(tag.id)
        } else {
            expandedTagIDs.insert(tag.id)
        }
    }

    func expandAll() {
        expandedTagIDs.formUnion(allTags.filter { !$0.children.isEmpty }.map(\.id))
    }

    func collapseAll() {
        expandedTagIDs.removeAll()
    }

    var areAllBranchesExpanded: Bool {
        let branchIDs = Set(allTags.filter { !$0.children.isEmpty }.map(\.id))
        return !branchIDs.isEmpty && branchIDs.isSubset(of: expandedTagIDs)
    }

    // MARK: - Detail

    func loadItems(for tag: Tag) {
        guard let context else { return }
        do {
            let descendantIDs = TagGraphTraverser.allDescendantIDs(of: tag)
            let items = try context.fetch(FetchDescriptor<Item>())
            tagItems = items
                .filter { item in item.tags.contains { descendantIDs.contains($0.id) } }
                .sorted { $0.modifiedAt > $1.modifiedAt }
        } catch {
            tagItems = []
            report(error, fallback: "Files for this tag couldn’t be loaded.")
        }
    }

    func parent(of tag: Tag) -> Tag? {
        incomingParents()[tag.id]?.first
    }

    func path(to tag: Tag) -> [Tag] {
        let incoming = incomingParents()
        var result = [tag]
        var currentID = tag.id
        var visited: Set<UUID> = [tag.id]

        while let parent = incoming[currentID]?.first, visited.insert(parent.id).inserted {
            result.append(parent)
            currentID = parent.id
        }
        return result.reversed()
    }

    func availableParents(for tag: Tag?) -> [Tag] {
        guard let tag else { return Self.sorted(allTags) }
        let excluded = TagGraphTraverser.allDescendantIDs(of: tag)
        return Self.sorted(allTags.filter { !excluded.contains($0.id) })
    }

    // MARK: - Mutations

    @discardableResult
    func createTag(
        name: String,
        colorHex: String,
        sfSymbol: String,
        parent: Tag?
    ) -> Bool {
        guard let context else { return false }
        clearError()

        let tag = Tag(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: colorHex,
            sfSymbol: sfSymbol
        )
        context.insert(tag)
        if let parent, !parent.children.contains(where: { $0.id == tag.id }) {
            parent.children.append(tag)
        }

        return saveAndReload(fallback: "The tag couldn’t be created.")
    }

    @discardableResult
    func updateTag(
        _ tag: Tag,
        name: String,
        colorHex: String,
        sfSymbol: String,
        parent: Tag?
    ) -> Bool {
        clearError()
        guard canMove(tag, to: parent) else { return false }

        tag.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tag.colorHex = colorHex
        tag.sfSymbol = sfSymbol
        replaceParent(of: tag, with: parent)

        return saveAndReload(fallback: "The tag couldn’t be saved.")
    }

    @discardableResult
    func moveTag(_ tag: Tag, to parent: Tag?) -> Bool {
        clearError()
        guard canMove(tag, to: parent) else { return false }
        replaceParent(of: tag, with: parent)
        return saveAndReload(fallback: "The tag couldn’t be moved.")
    }

    @discardableResult
    func deleteTagPromotingChildren(_ tag: Tag) -> Bool {
        guard let context else { return false }
        clearError()

        let currentParent = parent(of: tag)
        let children = Self.sorted(tag.children)

        for candidate in allTags {
            candidate.children.removeAll { $0.id == tag.id }
        }
        tag.children.removeAll()

        if let currentParent {
            for child in children where !currentParent.children.contains(where: { $0.id == child.id }) {
                currentParent.children.append(child)
            }
        }

        context.delete(tag)
        expandedTagIDs.remove(tag.id)
        return saveAndReload(fallback: "The tag couldn’t be deleted.")
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Relationship maintenance

    private func normalizeLegacyMultipleParents() throws {
        guard let context else { return }
        let tags = try context.fetch(FetchDescriptor<Tag>())
        var changed = false

        for tag in tags {
            let parents = Self.sorted(tags.filter { parent in
                parent.children.contains(where: { $0.id == tag.id })
            })
            guard parents.count > 1 else { continue }

            for extraParent in parents.dropFirst() {
                extraParent.children.removeAll { $0.id == tag.id }
                changed = true
            }
        }

        if changed { try context.save() }
    }

    private func canMove(_ tag: Tag, to parent: Tag?) -> Bool {
        guard let parent else { return true }
        guard !TagGraphTraverser.wouldCreateCycle(adding: parent, to: tag) else {
            errorMessage = "A tag can’t be moved inside itself or one of its subtags."
            return false
        }
        return true
    }

    private func replaceParent(of tag: Tag, with parent: Tag?) {
        for candidate in allTags {
            candidate.children.removeAll { $0.id == tag.id }
        }
        if let parent, !parent.children.contains(where: { $0.id == tag.id }) {
            parent.children.append(tag)
        }
    }

    private func incomingParents() -> [UUID: [Tag]] {
        var result: [UUID: [Tag]] = [:]
        for parent in allTags {
            for child in parent.children {
                result[child.id, default: []].append(parent)
            }
        }
        for key in result.keys {
            result[key] = Self.sorted(result[key] ?? [])
        }
        return result
    }

    @discardableResult
    private func saveAndReload(fallback: String) -> Bool {
        guard let context else { return false }
        do {
            try context.save()
            try loadTags()
            return true
        } catch {
            context.rollback()
            report(error, fallback: fallback)
            reload()
            return false
        }
    }

    private func report(_ error: Error, fallback: String) {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = description.isEmpty ? fallback : "\(fallback) \(description)"
    }

    nonisolated static func sorted(_ tags: [Tag]) -> [Tag] {
        tags.sorted { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return comparison == .orderedAscending
        }
    }
}
