import Foundation
import SwiftData
import Combine

@Observable
@MainActor
final class HomeViewModel {

    // MARK: - Search state

    var searchText: String = ""
    var isSearching: Bool  { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Results

    var searchResults: [Item] = []
    var pinnedItems: [Item]   = []
    var recentItems: [Item]   = []
    var frequentItems: [Item] = []
    var recentlyAdded: [Item] = []

    // MARK: - Search history

    var recentSearches: [SearchHistoryEntry] = []

    // MARK: - UI state

    var isLoading: Bool  = false
    var sortOrder: SearchService.SortOrder = .modifiedAt
    var selectedTag: Tag? = nil

    // MARK: - Filter state

    var selectedFileTypes: Set<FileType> = []
    var filterDateStart: Date? = nil
    var filterDateEnd: Date? = nil

    var hasActiveFilters: Bool {
        !selectedFileTypes.isEmpty || filterDateStart != nil || filterDateEnd != nil
    }

    func resetFilters() {
        selectedFileTypes = []
        filterDateStart = nil
        filterDateEnd = nil
    }

    // MARK: - Context

    private var context: ModelContext?

    // MARK: - Init

    func setup(context: ModelContext) {
        self.context = context
        loadHomeSections()
        loadSearchHistory()
    }

    // MARK: - Search

    func performSearch() {
        guard let context else { return }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty || selectedTag != nil else {
            searchResults = []
            return
        }

        isLoading = true
        do {
            let dateRange: ClosedRange<Date>? = {
                guard let start = filterDateStart else { return nil }
                let end = filterDateEnd ?? Date()
                return start <= end ? start...end : end...start
            }()
            searchResults = try SearchService.search(
                query: query,
                tagFilter: selectedTag,
                fileTypeFilter: selectedFileTypes.isEmpty ? nil : selectedFileTypes,
                dateRange: dateRange,
                sortOrder: sortOrder,
                context: context
            )
        } catch {
            searchResults = []
        }
        isLoading = false
    }

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            recordSearch(query: query)
        }
    }

    func clearSearch() {
        searchText = ""
        selectedTag = nil
        searchResults = []
    }

    // MARK: - Home sections

    func loadHomeSections() {
        guard let context else { return }
        pinnedItems   = (try? context.fetch(FetchDescriptor<Item>(
            predicate: #Predicate { $0.isPinned },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        ))) ?? []
        recentItems   = (try? SearchService.recentItems(limit: 10, context: context))   ?? []
        frequentItems = (try? SearchService.frequentItems(limit: 6, context: context))  ?? []
        recentlyAdded = (try? SearchService.recentlyAddedItems(limit: 20, context: context)) ?? []
    }

    // MARK: - Search history

    func loadSearchHistory() {
        guard let context else { return }
        var descriptor = FetchDescriptor<SearchHistoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        recentSearches = (try? context.fetch(descriptor)) ?? []
    }

    func applyRecentSearch(_ entry: SearchHistoryEntry) {
        searchText = entry.query
        performSearch()
    }

    func deleteSearchHistory(_ entry: SearchHistoryEntry) {
        context?.delete(entry)
        try? context?.save()
        loadSearchHistory()
    }

    func clearAllSearchHistory() {
        recentSearches.forEach { context?.delete($0) }
        try? context?.save()
        recentSearches = []
    }

    private func recordSearch(query: String) {
        guard let context else { return }
        // Update existing entry or create new one
        if let existing = recentSearches.first(where: { $0.query.lowercased() == query.lowercased() }) {
            existing.recordUse()
        } else {
            let entry = SearchHistoryEntry(query: query)
            context.insert(entry)
        }
        try? context.save()
        loadSearchHistory()
    }

    // MARK: - Item interaction

    func openItem(_ item: Item) {
        item.markOpened()
        try? context?.save()
        loadHomeSections()
    }

    // MARK: - Bulk select

    var isSelectMode: Bool = false
    var selectedIDs: Set<UUID> = []

    func enterSelectMode() {
        isSelectMode = true
        selectedIDs = []
    }

    func exitSelectMode() {
        isSelectMode = false
        selectedIDs = []
    }

    func toggleSelection(_ item: Item) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func bulkDelete(localStorage: LocalFileService? = nil) {
        guard let context else { return }
        let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        for item in all where selectedIDs.contains(item.id) {
            if let path = item.localFilePath, let ls = localStorage {
                Task { try? await ls.delete(relativePath: path) }
            }
            context.delete(item)
        }
        try? context.save()
        HapticFeedback.success()
        exitSelectMode()
        loadHomeSections()
    }

    func bulkTag(_ tag: Tag) {
        guard let context else { return }
        let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        for item in all where selectedIDs.contains(item.id) {
            if !item.tags.contains(where: { $0.id == tag.id }) {
                item.tags.append(tag)
            }
        }
        try? context.save()
        HapticFeedback.success()
        exitSelectMode()
        loadHomeSections()
    }

    func bulkFavorite() {
        guard let context else { return }
        let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        // Toggle: if all selected are already favorites, unfavorite; otherwise favorite all
        let selectedItems = all.filter { selectedIDs.contains($0.id) }
        let allFavorited = selectedItems.allSatisfy(\.isFavorite)
        for item in selectedItems {
            item.isFavorite = !allFavorited
        }
        try? context.save()
        HapticFeedback.light()
        exitSelectMode()
        loadHomeSections()
    }
}
