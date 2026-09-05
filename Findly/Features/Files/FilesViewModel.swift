import Foundation
import SwiftData

@Observable
@MainActor
final class FilesViewModel {

    // MARK: - Pagination

    static let pageSize = 25
    static let overscanMultiplier = 3

    var items: [Item] = []
    var currentOffset = 0        // raw DB position (before post-filters)
    var isLoadingMore = false
    var hasMorePages = true

    // MARK: - Filter state

    var sortOrder: SearchService.SortOrder = .modifiedAt
    var selectedFileTypes: Set<FileType> = []
    var filterDateStart: Date? = nil
    var filterDateEnd: Date? = nil

    var hasActiveFilters: Bool {
        !selectedFileTypes.isEmpty || filterDateStart != nil || filterDateEnd != nil
    }

    var hasActiveRefinements: Bool {
        hasActiveFilters || sortOrder != .modifiedAt
    }

    var activeFilterCount: Int {
        selectedFileTypes.count + ((filterDateStart != nil || filterDateEnd != nil) ? 1 : 0)
    }

    var itemCountSummary: String {
        if isLoadingMore && items.isEmpty { return "Loading files…" }
        let noun = items.count == 1 ? "file" : "files"
        return hasMorePages ? "\(items.count) \(noun) loaded" : "\(items.count) \(noun)"
    }

    var refinementAccessibilityValue: String {
        switch (activeFilterCount, sortOrder == .modifiedAt) {
        case (0, true): return "No active refinements"
        case (0, false): return "Custom sort"
        case (let count, true): return "\(count) active filter\(count == 1 ? "" : "s")"
        case (let count, false): return "\(count) active filter\(count == 1 ? "" : "s"), custom sort"
        }
    }

    var dateFilterSummary: String {
        switch (filterDateStart, filterDateEnd) {
        case (nil, nil):
            return "Any time"
        case (let start?, nil):
            return "From \(start.formatted(date: .abbreviated, time: .omitted))"
        case (nil, let end?):
            return "Through \(end.formatted(date: .abbreviated, time: .omitted))"
        case (let start?, let end?):
            return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    // MARK: - Select mode

    var isSelectMode = false
    var selectedIDs: Set<UUID> = []

    // MARK: - Layout

    enum LayoutStyle { case list, grid }
    var layoutStyle: LayoutStyle = .list

    // MARK: - Context

    private var context: ModelContext?
    private var loadRevision = 0

    // MARK: - Setup

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
        if items.isEmpty { loadNextPage() }
        guard vaultWipedObserver == nil else { return }
        vaultWipedObserver = NotificationCenter.default.addObserver(
            forName: .vaultDataWiped,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.loadRevision += 1
                self?.items = []
                self?.currentOffset = 0
                self?.isLoadingMore = false
                self?.hasMorePages = true
            }
        }
        itemSavedObserver = NotificationCenter.default.addObserver(
            forName: .itemSaved,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resetAndReload()
            }
        }
    }


    // MARK: - Pagination

    func loadNextPage() {
        guard !isLoadingMore, hasMorePages, let context else { return }
        isLoadingMore = true
        let revision = loadRevision
        let requestedSort = sortOrder
        let requestedTypes = selectedFileTypes
        let requestedStart = filterDateStart
        let requestedEnd = filterDateEnd
        let startingOffset = currentOffset

        Task { @MainActor in
            defer {
                if revision == loadRevision {
                    isLoadingMore = false
                }
            }

            guard revision == loadRevision else { return }

            let needsPostFilter = !requestedTypes.isEmpty
            let batchSize = needsPostFilter
                ? FilesViewModel.pageSize * FilesViewModel.overscanMultiplier
                : FilesViewModel.pageSize
            var nextOffset = startingOffset
            var page: [Item] = []

            repeat {
                guard revision == loadRevision else { return }

                var descriptor = FetchDescriptor<Item>(sortBy: requestedSort.sortDescriptors)
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = nextOffset

                // Build date predicate using concrete let-bindings (required by #Predicate macro)
                if let start = requestedStart, let end = requestedEnd {
                    let s = min(start, end)
                    let e = max(start, end)
                    descriptor.predicate = #Predicate<Item> { $0.createdAt >= s && $0.createdAt <= e }
                } else if let start = requestedStart {
                    let s = start
                    descriptor.predicate = #Predicate<Item> { $0.createdAt >= s }
                } else if let end = requestedEnd {
                    let e = end
                    descriptor.predicate = #Predicate<Item> { $0.createdAt <= e }
                }

                let batch: [Item]
                do {
                    batch = try context.fetch(descriptor)
                } catch {
                    hasMorePages = false
                    return
                }

                if batch.isEmpty {
                    hasMorePages = false
                    break
                }

                let filtered = requestedTypes.isEmpty
                    ? batch
                    : batch.filter { requestedTypes.contains($0.fileType) }

                page.append(contentsOf: filtered)
                nextOffset += batch.count

                if batch.count < batchSize {
                    hasMorePages = false
                    break
                }
            } while needsPostFilter && page.count < FilesViewModel.pageSize

            guard revision == loadRevision else { return }
            items.append(contentsOf: page)
            currentOffset = nextOffset
        }
    }

    func resetAndReload() {
        loadRevision += 1
        items = []
        currentOffset = 0
        hasMorePages = true
        isLoadingMore = false
        loadNextPage()
    }

    // MARK: - Refinements

    func applyRefinements(
        fileTypes: Set<FileType>,
        sortOrder newSortOrder: SearchService.SortOrder,
        dateStart: Date?,
        dateEnd: Date?
    ) {
        let calendar = Calendar.current
        let orderedStart: Date?
        let orderedEnd: Date?
        if let dateStart, let dateEnd {
            orderedStart = min(dateStart, dateEnd)
            orderedEnd = max(dateStart, dateEnd)
        } else {
            orderedStart = dateStart
            orderedEnd = dateEnd
        }

        let normalizedStart = orderedStart.map(calendar.startOfDay(for:))
        let normalizedEnd = orderedEnd.flatMap { date in
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))?
                .addingTimeInterval(-1)
        }

        guard selectedFileTypes != fileTypes ||
                sortOrder != newSortOrder ||
                filterDateStart != normalizedStart ||
                filterDateEnd != normalizedEnd else { return }

        selectedFileTypes = fileTypes
        sortOrder = newSortOrder
        filterDateStart = normalizedStart
        filterDateEnd = normalizedEnd
        resetAndReload()
    }

    func setSortOrder(_ newValue: SearchService.SortOrder) {
        guard sortOrder != newValue else { return }
        sortOrder = newValue
        resetAndReload()
    }

    func removeFileType(_ type: FileType) {
        guard selectedFileTypes.remove(type) != nil else { return }
        resetAndReload()
    }

    func clearDateFilter() {
        guard filterDateStart != nil || filterDateEnd != nil else { return }
        filterDateStart = nil
        filterDateEnd = nil
        resetAndReload()
    }

    func clearFilters() {
        guard hasActiveFilters else { return }
        selectedFileTypes.removeAll()
        filterDateStart = nil
        filterDateEnd = nil
        resetAndReload()
    }

    // MARK: - Select mode

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

    func toggleLayout() {
        layoutStyle = layoutStyle == .list ? .grid : .list
    }

    // MARK: - Bulk actions

    func bulkDelete(localStorage: LocalFileService?) {
        guard let context else { return }
        let targets = items.filter { selectedIDs.contains($0.id) }
        for item in targets {
            if let path = item.localFilePath, let ls = localStorage {
                Task { try? await ls.delete(relativePath: path) }
            }
            context.delete(item)
        }
        try? context.save()
        HapticFeedback.success()
        items.removeAll { selectedIDs.contains($0.id) }
        exitSelectMode()
    }

    func bulkTag(_ tag: Tag) {
        guard let context else { return }
        let targets = items.filter { selectedIDs.contains($0.id) }
        for item in targets {
            if !item.tags.contains(where: { $0.id == tag.id }) {
                item.tags.append(tag)
                item.markModified()
            }
        }
        try? context.save()
        HapticFeedback.success()
        exitSelectMode()
    }

    func bulkFavorite() {
        guard let context else { return }
        let targets = items.filter { selectedIDs.contains($0.id) }
        let allFavorited = targets.allSatisfy(\.isFavorite)
        for item in targets {
            item.isFavorite = !allFavorited
            item.markModified()
        }
        try? context.save()
        HapticFeedback.light()
        exitSelectMode()
    }
}
