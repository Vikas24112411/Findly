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
    var recentItems: [Item]   = []
    var frequentItems: [Item] = []
    var recentlyAdded: [Item] = []

    // MARK: - Search history

    var recentSearches: [SearchHistoryEntry] = []

    // MARK: - UI state

    var isLoading: Bool  = false
    var sortOrder: SearchService.SortOrder = .modifiedAt
    var selectedTag: Tag? = nil

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
            searchResults = try SearchService.search(
                query: query,
                tagFilter: selectedTag,
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
}
