import SwiftUI
import SwiftData

struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var viewModel = HomeViewModel()
    @State private var scrollOffset: CGFloat = 0
    @AppStorage("showRecentItems") private var showRecentItems = true
    @AppStorage("showFrequentItems") private var showFrequentItems = true

    private var titleProgress: CGFloat {
        scrollProgress(from: scrollOffset)
    }

    private var inlineTitle: String { "Findly" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    LargeTitleHeader(title: "Findly", progress: scrollProgress(from: scrollOffset))
                    homeContent
                }
            }
            .background(AppTheme.Colors.groupedBG)
            .trackScrollOffset($scrollOffset)
            .navTransitionTitle(inlineTitle, progress: titleProgress)
            .onAppear {
                viewModel.setup(context: modelContext)
            }
        }
    }

    // MARK: - Home content

    @ViewBuilder
    private var homeContent: some View {
        VStack(spacing: AppTheme.Spacing.xLarge) {

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
