import SwiftUI
import SwiftData

struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var viewModel = HomeViewModel()
    @State private var showFilterSheet = false
    @State private var showBulkTagPicker = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        if viewModel.isSearching {
                            SearchResultsView(
                                results: viewModel.searchResults,
                                isLoading: viewModel.isLoading,
                                query: viewModel.searchText,
                                activeFileTypes: viewModel.selectedFileTypes,
                                isSelectMode: viewModel.isSelectMode,
                                selectedIDs: viewModel.selectedIDs,
                                onOpen: { viewModel.openItem($0) },
                                onToggleSelect: { viewModel.toggleSelection($0) }
                            )
                        } else {
                            homeContent
                        }
                    }
                }
                .background(AppTheme.Colors.groupedBG)

                if viewModel.isSelectMode {
                    BulkActionsBar(
                        selectedCount: viewModel.selectedIDs.count,
                        onTag: { showBulkTagPicker = true },
                        onFavorite: { viewModel.bulkFavorite() },
                        onDelete: { viewModel.bulkDelete(localStorage: appContainer.localStorage) },
                        onCancel: { viewModel.exitSelectMode() }
                    )
                }
            }
            .navigationTitle(viewModel.isSelectMode ? "\(viewModel.selectedIDs.count) Selected" : "Findly")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search your vault..."
            )
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.performSearch()
            }
            .onSubmit(of: .search) {
                viewModel.submitSearch()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: AppTheme.Spacing.medium) {
                        if viewModel.isSelectMode {
                            Button("Done") { viewModel.exitSelectMode() }
                                .foregroundStyle(AppTheme.Colors.accent)
                        } else {
                            Button { viewModel.enterSelectMode() } label: {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            }
                            Button { showFilterSheet = true } label: {
                                Image(systemName: viewModel.hasActiveFilters
                                      ? "line.3.horizontal.decrease.circle.fill"
                                      : "line.3.horizontal.decrease.circle")
                                .foregroundStyle(viewModel.hasActiveFilters
                                                 ? AppTheme.Colors.accent
                                                 : AppTheme.Colors.secondaryLabel)
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
                    viewModel.bulkTag(tag)
                }
            }
            .onAppear {
                viewModel.setup(context: modelContext)
            }
        }
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
            if !viewModel.recentItems.isEmpty {
                RecentItemsSection(
                    title: "Continue Where You Left Off",
                    items: viewModel.recentItems,
                    onOpen: { viewModel.openItem($0) }
                )
            }

            // Frequently opened
            if !viewModel.frequentItems.isEmpty {
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
                && viewModel.recentItems.isEmpty
                && viewModel.frequentItems.isEmpty {
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
                    let isSelected = viewModel.selectedIDs.contains(item.id)
                    if viewModel.isSelectMode {
                        ItemCardView(item: item, isSelectMode: true, isSelected: isSelected)
                            .onTapGesture { viewModel.toggleSelection(item) }
                    } else {
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            ItemCardView(item: item)
                        }
                        .buttonStyle(.plain)
                    }
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
                        Image(systemName: tag.sfSymbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: tag.colorHex))
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
