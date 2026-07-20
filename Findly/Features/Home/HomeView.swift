import SwiftUI
import SwiftData

struct HomeView: View {

    var onSearch: (Set<FileType>, Tag?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @State private var viewModel = HomeViewModel()
    @State private var scrollOffset: CGFloat = 0
    @State private var showSettings = false

    @AppStorage("appearanceMode")     private var appearanceMode     = "system"
    @AppStorage("showRecentItems")    private var showRecentItems    = true
    @AppStorage("showFrequentItems")  private var showFrequentItems  = true
    @AppStorage("showPinnedItems")    private var showPinnedItems    = true
    @AppStorage("showFavoriteItems")  private var showFavoriteItems  = false

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
            // Reserve space so scroll content doesn't hide behind the bottom pill bar
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 95) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .preferredColorScheme(appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : nil)
            }
            .onAppear {
                viewModel.setup(context: modelContext)
            }
        }
    }

    // MARK: - Home content

    @ViewBuilder
    private var homeContent: some View {
        VStack(spacing: AppTheme.Spacing.base) {

            if showRecentItems && !viewModel.recentItems.isEmpty {
                recentShelfSection
            }

            if showFrequentItems && !viewModel.frequentItems.isEmpty {
                mostUsedShelfSection
            }

            if showPinnedItems && !viewModel.pinnedItems.isEmpty {
                pinnedShelfSection
            }

            if showFavoriteItems && !viewModel.favoriteItems.isEmpty {
                favoritesShelfSection
            }

            quickFilterChipsSection

            if !viewModel.allTags.isEmpty {
                browseByTagSection
            }

            if viewModel.recentItems.isEmpty
                && viewModel.frequentItems.isEmpty
                && viewModel.pinnedItems.isEmpty
                && viewModel.favoriteItems.isEmpty
                && viewModel.allTags.isEmpty {
                emptyStateView
            }
        }
        .padding(.top, AppTheme.Spacing.small)
        .padding(.bottom, AppTheme.Spacing.large)
    }

    // MARK: - Quick filter chips

    private var quickFilterChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(FileType.allCases.filter { $0 != .other }, id: \.self) { type in
                    Button {
                        onSearch([type], nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: type.sfSymbol)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(type.tintColor)
                                .frame(width: 22, height: 22)
                                .background(type.tintColor.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(type.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.label)
                        }
                        .padding(.horizontal, AppTheme.Spacing.medium)
                        .padding(.vertical, AppTheme.Spacing.small)
                        .background(type.tintColor.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.base)
        }
    }

    // MARK: - Recent shelf (large cards, recently opened)

    private var recentShelfSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Recent")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    ForEach(viewModel.recentItems) { item in
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            ItemCardView(item: item, style: .grid, titleLines: 1, availableTagWidth: 140 - 16)
                                .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { viewModel.openItem(item) })
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
            }
        }
    }

    // MARK: - Most Used shelf (medium cards, sorted by viewCount)

    private var mostUsedShelfSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Most Used")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    ForEach(viewModel.frequentItems) { item in
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            ItemCardView(item: item, style: .grid, titleLines: 1, availableTagWidth: 140 - 16)
                                .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { viewModel.openItem(item) })
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
            }
        }
    }

    // MARK: - Pinned shelf (medium cards, isPinned = true)

    private var pinnedShelfSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Pinned")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    ForEach(viewModel.pinnedItems) { item in
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            ItemCardView(item: item, style: .grid, titleLines: 1, availableTagWidth: 140 - 16)
                                .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { viewModel.openItem(item) })
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
            }
        }
    }

    // MARK: - Favorites shelf (medium cards, isFavorite = true)

    private var favoritesShelfSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Favorites")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    ForEach(viewModel.favoriteItems) { item in
                        NavigationLink(destination: ItemDetailView(item: item)) {
                            ItemCardView(item: item, style: .grid, titleLines: 1, availableTagWidth: 140 - 16)
                                .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { viewModel.openItem(item) })
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
            }
        }
    }

    // MARK: - Browse by Tag (pill row)

    private var browseByTagSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(viewModel.allTags.prefix(20)) { tag in
                        Button {
                            onSearch([], tag)
                        } label: {
                            tagPill(tag: tag)
                        }
                        .buttonStyle(.plain)
                    }
                    if viewModel.allTags.count > 20 {
                        Text("+\(viewModel.allTags.count - 20) more")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            .padding(.horizontal, AppTheme.Spacing.medium)
                            .padding(.vertical, AppTheme.Spacing.small)
                            .background(AppTheme.Colors.secondaryBG, in: Capsule())
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
        }
    }

    private func tagPill(tag: Tag) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tag.sfSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: tag.colorHex))
            Text(tag.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.Colors.label)
            Text("\(tag.totalItemCount)")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(Color(hex: tag.colorHex).opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(hex: tag.colorHex).opacity(0.18), lineWidth: 1))
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
    HomeView(onSearch: { _, _ in })
        .modelContainer(PersistenceController.preview.container)
        .environment(AppContainer())
}
