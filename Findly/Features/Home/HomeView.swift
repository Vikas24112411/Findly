import SwiftUI
import SwiftData

struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var viewModel = HomeViewModel()
    @State private var showFilterSheet = false
    @State private var showBulkDeleteConfirm = false
    @State private var showBulkTagPicker = false
    @State private var scrollOffset: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @AppStorage("showRecentItems") private var showRecentItems = true
    @AppStorage("showFrequentItems") private var showFrequentItems = true

    private var titleProgress: CGFloat {
        scrollProgress(from: scrollOffset)
    }

    private var inlineTitle: String { "Findly" }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        LargeTitleHeader(title: "Findly", progress: scrollProgress(from: scrollOffset))
                        LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                            Section {
                                if viewModel.isSearching {
                                    SearchResultsView(
                                        results: viewModel.searchResults,
                                        isLoading: viewModel.isLoading,
                                        query: viewModel.searchText,
                                        activeFileTypes: viewModel.selectedFileTypes,
                                        isSelectMode: viewModel.isSelectMode,
                                        selectedIDs: viewModel.selectedItemIDs,
                                        onOpen: { viewModel.openItem($0) },
                                        onToggleSelect: { viewModel.toggleItemSelection($0) }
                                    )
                                } else {
                                    homeContent
                                }
                            } header: {
                                InlineSearchBar(
                                    text: $viewModel.searchText,
                                    prompt: "Search your vault...",
                                    isFocused: $searchFocused,
                                    onSubmit: { viewModel.submitSearch() }
                                )
                            }
                        }
                    }
                }
                .background(AppTheme.Colors.groupedBG)
                .trackScrollOffset($scrollOffset)

                // Bulk action bar — floats above content when in select mode
                if viewModel.isSelectMode {
                    bulkActionBar
                }
            }
            .navTransitionTitle(inlineTitle, progress: titleProgress)
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.performSearch()
            }
            .onChange(of: viewModel.isSearching) { _, isSearching in
                if !isSearching { viewModel.exitSelectMode() }
            }
            .toolbar {
                // Leading: Cancel when in select mode
                if viewModel.isSelectMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { viewModel.exitSelectMode() }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.isSearching {
                        if viewModel.isSelectMode {
                            // Select-all / deselect-all toggle
                            let allSelected = viewModel.selectedItemIDs.count == viewModel.searchResults.count
                            Button(allSelected ? "Deselect All" : "Select All") {
                                allSelected ? viewModel.deselectAll() : viewModel.selectAll()
                            }
                        } else {
                            // Filter button (only shown while searching)
                            Button { showFilterSheet = true } label: {
                                Image(systemName: viewModel.hasActiveFilters
                                      ? "line.3.horizontal.decrease.circle.fill"
                                      : "line.3.horizontal.decrease.circle")
                                .foregroundStyle(viewModel.hasActiveFilters
                                                 ? AppTheme.Colors.accent
                                                 : AppTheme.Colors.secondaryLabel)
                            }
                            // Select button
                            Button { viewModel.toggleSelectMode() } label: {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet, onDismiss: {
                viewModel.performSearch()
            }) {
                FilterSheetView(
                    selectedFileTypes: $viewModel.selectedFileTypes,
                    sortOrder: $viewModel.sortOrder,
                    filterDateStart: $viewModel.filterDateStart,
                    filterDateEnd: $viewModel.filterDateEnd
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showBulkTagPicker) {
                BulkTagPickerSheet { tag in
                    viewModel.bulkAddTag(tag)
                }
            }
            .alert(
                "Delete \(viewModel.selectedItemIDs.count) item\(viewModel.selectedItemIDs.count == 1 ? "" : "s")?",
                isPresented: $showBulkDeleteConfirm
            ) {
                Button("Delete", role: .destructive) { performBulkDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Selected items will be removed from your vault and Google Drive.")
            }
            .onAppear {
                viewModel.setup(context: modelContext)
            }
        }
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                let items = viewModel.selectedItems
                let allPinned   = !items.isEmpty && items.allSatisfy(\.isPinned)
                let allFavorited = !items.isEmpty && items.allSatisfy(\.isFavorite)
                let hasSelection = !items.isEmpty

                bulkActionButton(
                    symbol: allPinned ? "pin.slash" : "pin",
                    label: allPinned ? "Unpin" : "Pin",
                    tint: hasSelection ? AppTheme.Colors.accent : AppTheme.Colors.tertiaryLabel
                ) { viewModel.bulkTogglePin() }
                .disabled(!hasSelection)

                bulkActionButton(
                    symbol: allFavorited ? "heart.slash" : "heart",
                    label: allFavorited ? "Unfavorite" : "Favorite",
                    tint: hasSelection ? AppTheme.Colors.accent : AppTheme.Colors.tertiaryLabel
                ) { viewModel.bulkToggleFavorite() }
                .disabled(!hasSelection)

                bulkActionButton(
                    symbol: "tag",
                    label: "Tag",
                    tint: hasSelection ? AppTheme.Colors.accent : AppTheme.Colors.tertiaryLabel
                ) { showBulkTagPicker = true }
                .disabled(!hasSelection)

                bulkActionButton(
                    symbol: "trash",
                    label: "Delete",
                    tint: hasSelection ? .red : AppTheme.Colors.tertiaryLabel
                ) { showBulkDeleteConfirm = true }
                .disabled(!hasSelection)
            }
            .padding(.vertical, AppTheme.Spacing.small)
            .background(.regularMaterial)
        }
    }

    private func bulkActionButton(
        symbol: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.xSmall)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bulk delete

    private func performBulkDelete() {
        let toDelete = viewModel.selectedItems
        viewModel.bulkDeleteFromContext()
        for item in toDelete {
            if let path = item.localFilePath {
                Task { try? await appContainer.localStorage.delete(relativePath: path) }
            }
            if let driveID = item.googleDriveFileID {
                Task { try? await appContainer.drive.deleteFile(driveFileID: driveID) }
            }
        }
        HapticFeedback.medium()
    }

    // MARK: - Home content (when not searching)

    @ViewBuilder
    private var homeContent: some View {
        VStack(spacing: AppTheme.Spacing.xLarge) {

            // Recent searches
            if !viewModel.recentSearches.isEmpty {
                recentSearchesSection
            }

            // Pinned files
            if !viewModel.pinnedItems.isEmpty {
                pinnedSection
            }

            // Continue where you left off
            if showRecentItems && !viewModel.recentItems.isEmpty {
                RecentItemsSection(
                    title: "Continue Where You Left Off",
                    items: viewModel.recentItems,
                    onOpen: { viewModel.openItem($0) }
                )
            }

            // Frequently opened
            if showFrequentItems && !viewModel.frequentItems.isEmpty {
                RecentItemsSection(
                    title: "Frequently Opened",
                    items: viewModel.frequentItems,
                    onOpen: { viewModel.openItem($0) }
                )
            }

            // Recently added
            if !viewModel.recentlyAdded.isEmpty {
                recentlyAddedSection
            }

            // Empty state
            if viewModel.recentlyAdded.isEmpty
                && (!showRecentItems || viewModel.recentItems.isEmpty)
                && (!showFrequentItems || viewModel.frequentItems.isEmpty) {
                emptyStateView
            }
        }
        .padding(.vertical, AppTheme.Spacing.large)
    }

    // MARK: - Pinned section

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Pinned")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    ForEach(viewModel.pinnedItems) { item in
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            ItemCardView(item: item, style: .grid)
                                .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
            }
        }
    }

    // MARK: - Recent searches

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(
                title: "Recent Searches",
                action: { viewModel.clearAllSearchHistory() },
                actionLabel: "Clear"
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(viewModel.recentSearches) { entry in
                        Button {
                            viewModel.applyRecentSearch(entry)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.xSmall) {
                                Image(systemName: "magnifyingglass")
                                    .font(.caption)
                                Text(entry.query)
                                    .font(AppTheme.Typography.subheadline)
                            }
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            .padding(.horizontal, AppTheme.Spacing.medium)
                            .padding(.vertical, AppTheme.Spacing.small)
                            .background(AppTheme.Colors.secondaryBG)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
            }
        }
    }

    // MARK: - Recently added grid

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Recently Added")
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppTheme.Spacing.medium
            ) {
                ForEach(viewModel.recentlyAdded.prefix(10)) { item in
                    NavigationLink(destination: ItemDetailView(item: item)) {
                        ItemCardView(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.base)
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        EmptyStateView(
            symbol: "sparkles",
            title: "Your vault is empty",
            subtitle: "Tap the + button to add your first file, note, or link.",
            actionLabel: nil
        )
        .padding(.top, AppTheme.Spacing.xxxLarge)
    }
}

// MARK: - Bulk tag picker

struct BulkTagPickerSheet: View {
    var onSelect: (Tag) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var allTags: [Tag] = []

    var body: some View {
        NavigationStack {
            List(allTags) { tag in
                Button {
                    onSelect(tag)
                    dismiss()
                } label: {
                    HStack(spacing: AppTheme.Spacing.medium) {
                        TagSymbolView(sfSymbol: tag.sfSymbol, color: Color(hex: tag.colorHex), size: 14)
                            .frame(width: 22, height: 22)
                            .background(Color(hex: tag.colorHex).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(tag.name)
                            .foregroundStyle(AppTheme.Colors.label)
                    }
                }
            }
            .navigationTitle("Add Tag to Selected")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                allTags = ((try? modelContext.fetch(FetchDescriptor<Tag>(
                    sortBy: [SortDescriptor(\.name)]
                ))) ?? [])
            }
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .modelContainer(PersistenceController.preview.container)
        .environment(AppContainer())
}
