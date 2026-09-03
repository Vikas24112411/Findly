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
    var favoriteItems: [Item] = []
    var allTags: [Tag]        = []

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

    // MARK: - Bulk select state

    var isSelectMode: Bool = false
    var selectedItemIDs: Set<UUID> = []

    var selectedItems: [Item] {
        searchResults.filter { selectedItemIDs.contains($0.id) }
    }

    func toggleSelectMode() {
        isSelectMode.toggle()
        if !isSelectMode { selectedItemIDs = [] }
    }

    func exitSelectMode() {
        isSelectMode = false
        selectedItemIDs = []
    }

    func toggleItemSelection(_ item: Item) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func selectAll() {
        selectedItemIDs = Set(searchResults.map(\.id))
    }

    func deselectAll() {
        selectedItemIDs = []
    }

    // MARK: - Bulk operations

    func bulkTogglePin() {
        guard !selectedItems.isEmpty else { return }
        let allPinned = selectedItems.allSatisfy(\.isPinned)
        selectedItems.forEach { $0.isPinned = !allPinned }
        try? context?.save()
        loadHomeSections()
    }

    func bulkToggleFavorite() {
        guard !selectedItems.isEmpty else { return }
        let allFavorited = selectedItems.allSatisfy(\.isFavorite)
        selectedItems.forEach { $0.isFavorite = !allFavorited }
        try? context?.save()
        loadHomeSections()
    }

    func bulkAddTag(_ tag: Tag) {
        guard !selectedItems.isEmpty else { return }
        selectedItems.forEach { item in
            if !item.tags.contains(where: { $0.id == tag.id }) {
                item.tags.append(tag)
                item.markModified()
            }
        }
        try? context?.save()
    }

    /// Removes selected items from SwiftData. The caller is responsible for
    /// deleting local files and Drive copies (same pattern as the metadata inspector).
    func bulkDeleteFromContext() {
        guard let context else { return }
        selectedItems.forEach { context.delete($0) }
        try? context.save()
        selectedItemIDs = []
        isSelectMode = false
        loadHomeSections()
    }

    // MARK: - Context

    private var context: ModelContext?

    // MARK: - In-flight search task (for debounce)

    private var searchTask: Task<Void, Never>?

    // MARK: - Init

    private nonisolated(unsafe) var vaultWipedObserver: NSObjectProtocol?
    private nonisolated(unsafe) var itemSavedObserver: NSObjectProtocol?

    deinit {
        if let observer = vaultWipedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = itemSavedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setup(context: ModelContext) {
        self.context = context
        // Defer DB fetches so HomeView renders its empty state before hitting SQLite.
        // loadHomeSections() is called synchronously from mutation paths (bulkTogglePin etc.)
        // and from the itemSaved observer — only this initial call is deferred.
        Task { @MainActor in
            await Task.yield()
            self.loadHomeSections()
            self.loadSearchHistory()
        }
        // Register once per instance to clear cached [Item] arrays when all vault data
        // is wiped. Clearing happens synchronously on the main thread so the arrays are
        // empty before SwiftUI re-renders with the next await yield.
        guard vaultWipedObserver == nil else { return }
        vaultWipedObserver = NotificationCenter.default.addObserver(
            forName: .vaultDataWiped,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pinnedItems   = []
                self?.recentItems   = []
                self?.frequentItems = []
                self?.favoriteItems = []
                self?.allTags       = []
                self?.searchResults = []
            }
        }
        itemSavedObserver = NotificationCenter.default.addObserver(
            forName: .itemSaved,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.loadHomeSections()
            }
        }
    }


    // MARK: - Search

    func performSearch() {
        searchTask?.cancel()
        guard let context else { return }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty || selectedTag != nil || !selectedFileTypes.isEmpty else {
            searchResults = []
            return
        }
        isLoading = true
        searchTask = Task { @MainActor in
            // 250 ms debounce — cancel and restart on each keystroke so we only
            // hit the DB after the user pauses, not on every character typed.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                self.isLoading = false
                return
            }
            let dateRange: ClosedRange<Date>? = {
                guard let start = self.filterDateStart else { return nil }
                let end = self.filterDateEnd ?? Date()
                return start <= end ? start...end : end...start
            }()
            do {
                self.searchResults = try SearchService.search(
                    query: query,
                    tagFilter: self.selectedTag,
                    fileTypeFilter: self.selectedFileTypes.isEmpty ? nil : self.selectedFileTypes,
                    dateRange: dateRange,
                    sortOrder: self.sortOrder,
                    context: context
                )
            } catch {
                self.searchResults = []
            }
            self.isLoading = false
        }
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
        exitSelectMode()
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
        var favDescriptor = FetchDescriptor<Item>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        favDescriptor.fetchLimit = 10
        favoriteItems = (try? context.fetch(favDescriptor)) ?? []

        allTags = (try? context.fetch(FetchDescriptor<Tag>(
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
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
        // Prune to the most recent 50 entries — use fetchCount first to avoid
        // loading all entries when no pruning is needed.
        let count = (try? context.fetchCount(FetchDescriptor<SearchHistoryEntry>())) ?? 0
        if count > 50 {
            var pruneDesc = FetchDescriptor<SearchHistoryEntry>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            pruneDesc.fetchOffset = 50
            let toDelete = (try? context.fetch(pruneDesc)) ?? []
            toDelete.forEach { context.delete($0) }
            try? context.save()
        }
        loadSearchHistory()
    }

}
