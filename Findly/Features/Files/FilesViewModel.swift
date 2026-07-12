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

    // MARK: - Select mode

    var isSelectMode = false
    var selectedIDs: Set<UUID> = []

    // MARK: - Layout

    enum LayoutStyle { case list, grid }
    var layoutStyle: LayoutStyle = .list

    // MARK: - Context

    private var context: ModelContext?

    // MARK: - Setup

    func setup(context: ModelContext) {
        self.context = context
        if items.isEmpty { loadNextPage() }
    }

    // MARK: - Pagination

    func loadNextPage() {
        guard !isLoadingMore, hasMorePages, let context else { return }
        isLoadingMore = true

        Task { @MainActor in
            defer { isLoadingMore = false }

            let needsPostFilter = !selectedFileTypes.isEmpty
            let batchSize = needsPostFilter
                ? FilesViewModel.pageSize * FilesViewModel.overscanMultiplier
                : FilesViewModel.pageSize

            var descriptor = FetchDescriptor<Item>(sortBy: sortOrder.sortDescriptors)
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = currentOffset

            // Build date predicate using concrete let-bindings (required by #Predicate macro)
            if let start = filterDateStart, let end = filterDateEnd {
                let s = min(start, end)
                let e = max(start, end)
                descriptor.predicate = #Predicate<Item> { $0.createdAt >= s && $0.createdAt <= e }
            } else if let start = filterDateStart {
                let s = start
                descriptor.predicate = #Predicate<Item> { $0.createdAt >= s }
            } else if let end = filterDateEnd {
                let e = end
                descriptor.predicate = #Predicate<Item> { $0.createdAt <= e }
            }

            let batch: [Item]
            do {
                batch = try context.fetch(descriptor)
            } catch {
                return
            }

            if batch.isEmpty {
                hasMorePages = false
                return
            }

            // Post-filter: file type (enum array containment not reliably supported in SwiftData #Predicate)
            let filtered = selectedFileTypes.isEmpty
                ? batch
                : batch.filter { selectedFileTypes.contains($0.fileType) }

            items.append(contentsOf: filtered)
            currentOffset += batch.count

            if batch.count < batchSize {
                hasMorePages = false
            }
        }
    }

    func resetAndReload() {
        items = []
        currentOffset = 0
        hasMorePages = true
        isLoadingMore = false
        loadNextPage()
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
