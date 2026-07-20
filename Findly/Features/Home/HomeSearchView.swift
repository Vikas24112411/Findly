import SwiftUI
import SwiftData

struct HomeSearchView: View {

    @Binding var searchText: String
    @Binding var pendingConfig: SearchConfig?

    @State private var viewModel = HomeViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var showFilterSheet = false
    @State private var showBulkDeleteConfirm = false
    @State private var showBulkTagPicker = false

    var body: some View {
        ScrollView {
            if viewModel.isSearching || !viewModel.selectedFileTypes.isEmpty || viewModel.selectedTag != nil {
                activeFilterChips
                SearchResultsView(
                    results: viewModel.searchResults,
                    isLoading: viewModel.isLoading,
                    query: viewModel.searchText,
                    isSelectMode: viewModel.isSelectMode,
                    selectedIDs: viewModel.selectedItemIDs,
                    onOpen: { viewModel.openItem($0) },
                    onToggleSelect: { viewModel.toggleItemSelection($0) }
                )
            } else {
                emptyContent
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if viewModel.isSelectMode {
                bulkActionBar
            }
        }
        .background(AppTheme.Colors.groupedBG)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if viewModel.isSelectMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { viewModel.exitSelectMode() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let allSelected = viewModel.selectedItemIDs.count == viewModel.searchResults.count
                    Button(allSelected ? "Deselect All" : "Select All") {
                        allSelected ? viewModel.deselectAll() : viewModel.selectAll()
                    }
                }
            } else {
                if viewModel.isSearching || !viewModel.selectedFileTypes.isEmpty || viewModel.selectedTag != nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { showFilterSheet = true } label: {
                            Image(systemName: viewModel.hasActiveFilters
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(viewModel.hasActiveFilters
                                             ? AppTheme.Colors.accent
                                             : AppTheme.Colors.secondaryLabel)
                        }
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
            BulkTagPickerSheet { tag in viewModel.bulkAddTag(tag) }
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
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.performSearch()
        }
        .onChange(of: pendingConfig) { _, newConfig in
            guard let config = newConfig else { return }
            applyConfig(config)
            pendingConfig = nil
        }
        .onAppear {
            viewModel.setup(context: modelContext)
            viewModel.loadSearchHistory()
            if let config = pendingConfig {
                applyConfig(config)
                pendingConfig = nil
            }
        }
    }

    // MARK: - Apply pending search config from pills

    private func applyConfig(_ config: SearchConfig) {
        viewModel.resetFilters()
        viewModel.selectedFileTypes = config.fileTypes
        viewModel.selectedTag = config.tag
        viewModel.performSearch()
    }

    // MARK: - Active filter chips (tag + file types)

    private var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(Array(viewModel.selectedFileTypes), id: \.self) { type in
                    filterChip(
                        label: type.displayName,
                        symbol: type.sfSymbol,
                        color: type.tintColor
                    ) {
                        viewModel.selectedFileTypes.remove(type)
                        viewModel.performSearch()
                    }
                }
                if let tag = viewModel.selectedTag {
                    filterChip(
                        label: "#\(tag.name)",
                        symbol: tag.sfSymbol,
                        color: Color(hex: tag.colorHex)
                    ) {
                        viewModel.selectedTag = nil
                        viewModel.performSearch()
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.base)
            .padding(.top, AppTheme.Spacing.xSmall)
        }
    }

    private func filterChip(label: String, symbol: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Empty state content (suggestions + recents)

    private var emptyContent: some View {
        VStack(spacing: AppTheme.Spacing.xLarge) {
            suggestionsSection
            if !viewModel.recentSearches.isEmpty {
                recentsSection
            }
        }
        .padding(.vertical, AppTheme.Spacing.large)
    }

    // MARK: - Recents section

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(
                title: "Recents",
                action: { viewModel.clearAllSearchHistory() },
                actionLabel: "Clear"
            )
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                ForEach(viewModel.recentSearches.prefix(6)) { entry in
                    Button {
                        searchText = entry.query
                        viewModel.searchText = entry.query
                        viewModel.performSearch()
                    } label: {
                        HStack(spacing: AppTheme.Spacing.small) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            Text(entry.query)
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.Colors.label)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, AppTheme.Spacing.medium)
                        .padding(.vertical, AppTheme.Spacing.small)
                        .background(AppTheme.Colors.secondaryBG)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.full, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.base)
        }
    }

    // MARK: - Suggestions (file type icon grid)

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Browse by Type")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(FileType.allCases.filter { $0 != .other }, id: \.self) { type in
                        Button {
                            viewModel.resetFilters()
                            viewModel.selectedFileTypes = [type]
                            viewModel.performSearch()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: type.sfSymbol)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(type.tintColor)
                                    .frame(width: 26, height: 26)
                                    .background(type.tintColor.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                Text(type.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppTheme.Colors.label)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(type.tintColor.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.full, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
            }
        }
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                let items = viewModel.selectedItems
                let allPinned    = !items.isEmpty && items.allSatisfy(\.isPinned)
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
                Image(systemName: symbol).font(.system(size: 20))
                Text(label).font(.system(size: 10, weight: .medium))
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

}
