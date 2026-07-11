import SwiftUI
import SwiftData

struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.isSearching {
                        SearchResultsView(
                            results: viewModel.searchResults,
                            isLoading: viewModel.isLoading,
                            query: viewModel.searchText,
                            onOpen: { viewModel.openItem($0) }
                        )
                    } else {
                        homeContent
                    }
                }
            }
            .background(AppTheme.Colors.groupedBG)
            .navigationTitle("Findly")
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

// MARK: - Preview

#Preview {
    HomeView()
        .modelContainer(PersistenceController.preview.container)
        .environment(AppContainer())
}
