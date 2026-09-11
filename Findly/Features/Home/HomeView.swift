import SwiftUI
import SwiftData

struct HomeView: View {

    var onSearch: (Set<FileType>, Tag?) -> Void

    @Environment(FileViewerCoordinator.self) private var fileViewer
    @Query private var recentlyAddedItems: [Item]
    @Query private var pinnedItems: [Item]
    @Query private var recentItems: [Item]
    @Query private var frequentItems: [Item]
    @Query private var favoriteItems: [Item]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @ScaledMetric(relativeTo: .body) private var pinnedCardWidth: CGFloat = 140
    @State private var scrollOffset: CGFloat = 0
    @State private var showSettings = false

    @AppStorage("appearanceMode")     private var appearanceMode     = "system"
    @AppStorage("showRecentItems")    private var showRecentItems    = true
    @AppStorage("showFrequentItems")  private var showFrequentItems  = true
    @AppStorage("showPinnedItems")    private var showPinnedItems    = true
    @AppStorage("showFavoriteItems")  private var showFavoriteItems  = false

    init(onSearch: @escaping (Set<FileType>, Tag?) -> Void) {
        self.onSearch = onSearch
        _recentlyAddedItems = Query(HomeCollection.added.descriptor(limit: 20))
        _pinnedItems = Query(HomeCollection.pinned.descriptor())
        _recentItems = Query(HomeCollection.opened.descriptor(limit: 3))
        _frequentItems = Query(HomeCollection.frequent.descriptor(limit: 1))
        _favoriteItems = Query(HomeCollection.favorites.descriptor(limit: 1))
    }

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
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .preferredColorScheme(appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : nil)
            }

        }
    }

    // MARK: - Home content

    @ViewBuilder
    private var homeContent: some View {
        VStack(spacing: AppTheme.Spacing.xLarge) {
            if showPinnedItems && !pinnedItems.isEmpty {
                pinnedShelfSection
            }

            if showRecentItems && !recentItems.isEmpty {
                itemListSection(.opened, items: recentItems)
            }

            if hasShortcuts {
                shortcutsSection
            }

            if !recentlyAddedItems.isEmpty {
                itemListSection(.added, items: Array(recentlyAddedItems.prefix(2)))
            }

            if isVaultEmpty {
                emptyStateView
            } else {
                quickFilterChipsSection

                if !allTags.isEmpty {
                    browseByTagSection
                }
            }
        }
        .padding(.top, isVaultEmpty ? 0 : AppTheme.Spacing.small)
        .padding(.bottom, AppTheme.Spacing.large)
    }

    private var isVaultEmpty: Bool {
        recentlyAddedItems.isEmpty
            && recentItems.isEmpty
            && frequentItems.isEmpty
            && pinnedItems.isEmpty
            && favoriteItems.isEmpty
            && allTags.isEmpty
    }

    // MARK: - Quick filter chips

    private var quickFilterChipsSection: some View {
        DriftingFilterRow(direction: 1) {
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

    // MARK: - Essentials

    private var hasShortcuts: Bool {
        (showFavoriteItems && !favoriteItems.isEmpty)
            || (showFrequentItems && !frequentItems.isEmpty)
    }

    private func collectionHeader(_ collection: HomeCollection, actionLabel: String = "See all") -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(collection.title)
                .font(AppTheme.Typography.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            NavigationLink {
                HomeCollectionView(collection: collection)
            } label: {
                Text(actionLabel)
                    .font(AppTheme.Typography.subheadline)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("\(actionLabel) \(collection.title.lowercased())")
        }
        .padding(.horizontal, AppTheme.Spacing.base)
    }

    private var pinnedShelfSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            collectionHeader(.pinned, actionLabel: "View all")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                    ForEach(pinnedItems.filter(\.isAvailableForPresentation), id: \.persistentModelID) { item in
                        Button { fileViewer.open(item) } label: {
                            HomePinnedCard(item: item)
                                .frame(width: pinnedCardWidth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens file")
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
            }
            .accessibilityLabel("Pinned files")
        }
    }

    private func itemListSection(_ collection: HomeCollection, items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            collectionHeader(collection)
            VStack(spacing: 0) {
                ForEach(items.filter(\.isAvailableForPresentation), id: \.persistentModelID) { item in
                    Button { fileViewer.open(item) } label: {
                        HomeFileRow(item: item, collection: collection)
                            .padding(AppTheme.Spacing.medium)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens file")
                    if item.persistentModelID != items.last?.persistentModelID {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(AppTheme.Colors.background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .padding(.horizontal, AppTheme.Spacing.base)
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: "Shortcuts")
            VStack(spacing: 0) {
                if showFavoriteItems && !favoriteItems.isEmpty {
                    shortcut(.favorites, symbol: "heart.fill", tint: AppTheme.Colors.favoriteTint)
                }
                if showFavoriteItems && !favoriteItems.isEmpty && showFrequentItems && !frequentItems.isEmpty {
                    Divider().padding(.leading, 64)
                }
                if showFrequentItems && !frequentItems.isEmpty {
                    shortcut(.frequent, symbol: "chart.bar.fill", tint: AppTheme.Colors.accent)
                }
            }
            .background(AppTheme.Colors.background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .padding(.horizontal, AppTheme.Spacing.base)
        }
    }

    private func shortcut(_ collection: HomeCollection, symbol: String, tint: Color) -> some View {
        NavigationLink {
            HomeCollectionView(collection: collection)
        } label: {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 44)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                Text(collection.title)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.label)
                Spacer(minLength: AppTheme.Spacing.small)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
            }
            .padding(AppTheme.Spacing.medium)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Browse by Tag (pill row)

    private var browseByTagSection: some View {
        DriftingFilterRow(direction: -1) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(allTags.prefix(20)) { tag in
                        Button {
                            onSearch([], tag)
                        } label: {
                            tagPill(tag: tag)
                        }
                        .buttonStyle(.plain)
                    }
                    if allTags.count > 20 {
                        Text("+\(allTags.count - 20) more")
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
            subtitle: "Tap + to add an item.",
            placement: .page
        )
    }
}

// Keep the native scroll view and buttons so users can take over at any time.
private struct DriftingFilterRow<Content: View>: View {
    let direction: CGFloat
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @State private var position = ScrollPosition(x: 0)
    @State private var cycleWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var visible = false
    @State private var userControlled = false

    private var repeats: Bool {
        !reduceMotion && !voiceOver && cycleWidth > viewportWidth && viewportWidth > 0
    }

    private var paused: Bool {
        !repeats || !visible || userControlled || scenePhase != .active
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    content
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                            cycleWidth = $0
                        }
                    if repeats {
                        content
                        content
                    }
                }
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.width } action: { _, width in
                viewportWidth = width
            }
            .onScrollPhaseChange { _, phase in
                // Leave the row under manual control until it leaves the screen.
                if phase == .tracking || phase == .interacting {
                    userControlled = true
                }
            }
            .onScrollVisibilityChange(threshold: 0.1) { isVisible in
                visible = isVisible
                if !isVisible { userControlled = false }
            }
            .onChange(of: repeats) { _, enabled in
                offset = enabled ? cycleWidth : 0
                position.scrollTo(x: offset)
            }
            .onChange(of: visible) { _, isVisible in
                if isVisible && repeats {
                    offset = cycleWidth
                    position.scrollTo(x: offset)
                }
            }
            .onChange(of: timeline.date) { oldDate, newDate in
                guard !paused else { return }
                // Twelve points per second; clamp elapsed time after interruptions.
                let elapsed = min(newDate.timeIntervalSince(oldDate), 1.0 / 15)
                offset += direction * 12 * elapsed
                if offset >= cycleWidth * 2 { offset -= cycleWidth }
                if offset < cycleWidth { offset += cycleWidth }
                position.scrollTo(x: offset)
            }
        }
    }
}

// MARK: - Live Home collections

enum HomeCollection {
    case pinned, opened, added, favorites, frequent

    var title: String {
        switch self {
        case .pinned: "Pinned"
        case .opened: "Recently opened"
        case .added: "Recently added"
        case .favorites: "Favorites"
        case .frequent: "Most used"
        }
    }

    func descriptor(limit: Int? = nil) -> FetchDescriptor<Item> {
        var descriptor: FetchDescriptor<Item>
        switch self {
        case .pinned:
            descriptor = FetchDescriptor(predicate: #Predicate<Item> { $0.isPinned },
                                         sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        case .opened:
            descriptor = FetchDescriptor(predicate: #Predicate<Item> { $0.lastOpenedAt != nil },
                                         sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)])
        case .added:
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        case .favorites:
            descriptor = FetchDescriptor(predicate: #Predicate<Item> { $0.isFavorite },
                                         sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        case .frequent:
            descriptor = FetchDescriptor(predicate: #Predicate<Item> { $0.viewCount > 0 },
                                         sortBy: [SortDescriptor(\.viewCount, order: .reverse)])
        }
        descriptor.fetchLimit = limit
        return descriptor
    }
}

private struct HomeCollectionView: View {
    let collection: HomeCollection
    @Query private var items: [Item]
    @Environment(FileViewerCoordinator.self) private var fileViewer

    init(collection: HomeCollection) {
        self.collection = collection
        _items = Query(collection.descriptor())
    }

    var body: some View {
        List {
            ForEach(items.filter(\.isAvailableForPresentation), id: \.persistentModelID) { item in
                Button { fileViewer.open(item) } label: {
                    HomeFileRow(item: item, collection: collection)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens file")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 95) }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No items yet", systemImage: "doc",
                                       description: Text("Items will appear here when you add, open, or save them to this collection."))
            }
        }
    }
}

private struct HomePinnedCard: View {
    let item: Item
    @State private var thumbnail: UIImage?

    private var pinnedCardAccessibilityLabel: String {
        var parts = [item.title, item.fileType.displayName]
        if !item.tags.isEmpty {
            parts.append(item.tags.map(\.name).joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        if item.isAvailableForPresentation {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .fill(item.fileType.tintColor.opacity(0.1))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: item.fileType.sfSymbol)
                            .font(.largeTitle)
                            .foregroundStyle(item.fileType.tintColor)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.pinnedTint)
                        .padding(6)
                        .background(AppTheme.Colors.background, in: Circle())
                        .padding(4)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                Text(item.title)
                    .font(AppTheme.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.fileType.displayName)
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .lineLimit(1)
            }
        }
        .padding(AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(AppTheme.Colors.background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pinnedCardAccessibilityLabel)
        .task(id: item.thumbnailData) {
            thumbnail = nil
            guard let data = item.thumbnailData else { return }
            let id = item.id
            let decoded = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.shared.image(for: id, data: data, targetSize: CGSize(width: 200, height: 200))
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = decoded
        }
    }
}

private struct HomeFileRow: View {
    let item: Item
    let collection: HomeCollection

    /// Leading subtitle: type + tags only. The time component lives in its own
    /// trailing label so it stays in a fixed column regardless of tag length.
    private var subtitle: String {
        var parts = [item.fileType.displayName]
        if let firstTag = item.tags.first {
            let remaining = item.tags.count - 1
            parts.append(remaining > 0 ? "\(firstTag.name) +\(remaining)" : firstTag.name)
        }
        return parts.joined(separator: " · ")
    }

    /// Trailing timestamp, fixed to the row's end column.
    private var timeText: String? {
        switch collection {
        case .opened:
            guard let date = item.lastOpenedAt else { return nil }
            return "Opened \(date.compactRelativeString)"
        case .frequent:
            return "\(item.viewCount) opens"
        default:
            return "Added \(item.createdAt.compactRelativeString)"
        }
    }

    var body: some View {
        if item.isAvailableForPresentation {
            content
        }
    }

    private var content: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            HomeFileIcon(item: item)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                Text(item.title)
                    .font(AppTheme.Typography.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xSmall) {
                if let timeText {
                    Text(timeText)
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        .lineLimit(1)
                }
                SyncStatusBadge(status: item.syncStatus, compactMode: true)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct HomeFileIcon: View {
    let item: Item

    var body: some View {
        if item.isAvailableForPresentation {
            content
        }
    }

    private var content: some View {
        Image(systemName: item.fileType.sfSymbol)
            .font(.title3)
            .foregroundStyle(item.fileType.tintColor)
            .frame(width: 40, height: 44)
            .background(item.fileType.tintColor.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            .accessibilityHidden(true)
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
        .environment(FileViewerCoordinator())
}
