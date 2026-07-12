import SwiftUI
import SwiftData

struct FilesView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var viewModel = FilesViewModel()
    @State private var showFilterSheet = false
    @State private var showBulkTagPicker = false
    @State private var scrollOffset: CGFloat = 0

    private var titleProgress: CGFloat {
        viewModel.isSelectMode ? 1.0 : scrollProgress(from: scrollOffset)
    }

    private var inlineTitle: String {
        viewModel.isSelectMode ? "\(viewModel.selectedIDs.count) Selected" : "Files"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        LargeTitleHeader(title: "Files", progress: scrollProgress(from: scrollOffset))
                        filesContent
                    }
                }
                .background(AppTheme.Colors.groupedBG)
                .trackScrollOffset($scrollOffset)

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
            .navTransitionTitle(inlineTitle, progress: titleProgress)
            .toolbar { filesToolbar }
            .sheet(isPresented: $showFilterSheet, onDismiss: {
                viewModel.resetAndReload()
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var filesToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: AppTheme.Spacing.medium) {
                if viewModel.isSelectMode {
                    Button("Done") { viewModel.exitSelectMode() }
                        .foregroundStyle(AppTheme.Colors.accent)
                } else {
                    Button { viewModel.toggleLayout() } label: {
                        Image(systemName: viewModel.layoutStyle == .list
                              ? "square.grid.2x2"
                              : "list.bullet")
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }
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

    // MARK: - Content

    @ViewBuilder
    private var filesContent: some View {
        if viewModel.items.isEmpty && !viewModel.isLoadingMore {
            EmptyStateView(
                symbol: "doc.on.doc",
                title: "No files",
                subtitle: viewModel.hasActiveFilters
                    ? "No files match the active filters."
                    : "Tap the + button to add your first file."
            )
            .padding(.top, AppTheme.Spacing.xxxLarge)
        } else {
            Group {
                switch viewModel.layoutStyle {
                case .list:
                    LazyVStack(spacing: AppTheme.Spacing.medium) {
                        ForEach(viewModel.items) { item in
                            itemCell(item, style: .row)
                                .padding(.horizontal, AppTheme.Spacing.base)
                        }
                    }
                case .grid:
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: AppTheme.Spacing.medium
                    ) {
                        ForEach(viewModel.items) { item in
                            itemCell(item, style: .grid)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.base)
                }
            }
            .padding(.vertical, AppTheme.Spacing.small)

            scrollSentinel
        }
    }

    // MARK: - Item cell

    @ViewBuilder
    private func itemCell(_ item: Item, style: ItemCardView.Style) -> some View {
        let isSelected = viewModel.selectedIDs.contains(item.id)
        if viewModel.isSelectMode {
            ItemCardView(item: item, style: style, isSelectMode: true, isSelected: isSelected)
                .onTapGesture { viewModel.toggleSelection(item) }
        } else {
            NavigationLink(destination: ItemDetailView(item: item)) {
                ItemCardView(item: item, style: style)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Infinite scroll sentinel

    @ViewBuilder
    private var scrollSentinel: some View {
        if viewModel.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.xLarge)
        } else if viewModel.hasMorePages {
            Color.clear
                .frame(height: 1)
                .onAppear { viewModel.loadNextPage() }
        }
    }
}

// MARK: - Preview

#Preview {
    FilesView()
        .modelContainer(PersistenceController.preview.container)
        .environment(AppContainer())
}
