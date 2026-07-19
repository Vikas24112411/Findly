import SwiftUI
import SwiftData

struct HomeSearchView: View {

    @State private var viewModel = HomeViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @FocusState private var searchFocused: Bool
    @State private var showFilterSheet = false
    @State private var showBulkDeleteConfirm = false
    @State private var showBulkTagPicker = false

    var body: some View {
        ScrollView {
            if viewModel.isSearching || !viewModel.selectedFileTypes.isEmpty {
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
                emptyContent
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if viewModel.isSelectMode {
                bulkActionBar
            } else {
                bottomSearchBar
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
                if viewModel.isSearching || !viewModel.selectedFileTypes.isEmpty {
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
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.performSearch()
        }
        .onAppear {
            viewModel.setup(context: modelContext)
            viewModel.loadSearchHistory()
            searchFocused = true
        }
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

    // MARK: - Bottom search bar

    private var bottomSearchBar: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                TextField("Search your vault...", text: $viewModel.searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { viewModel.submitSearch() }
                if !viewModel.searchText.isEmpty || !viewModel.selectedFileTypes.isEmpty {
                    Button {
                        viewModel.clearSearch()
                        viewModel.resetFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    }
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.full, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
            .animation(.easeInOut(duration: 0.15), value: viewModel.searchText.isEmpty)

            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.base)
        .padding(.vertical, AppTheme.Spacing.small)
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
