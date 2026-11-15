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
                HomeDiscoveryChips(allTags: allTags, slot: .home, onSearch: onSearch)
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
            .background(AppTheme.Colors.flatCard, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
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
            .background(AppTheme.Colors.flatCard, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
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

// MARK: - Discovery chips (shared by Home and Search)

/// The file-type and tag rows. Home uses them as shortcuts into Search; Search uses
/// them as toggles, so both screens show the same rows in the same style.
struct HomeDiscoveryChips: View {
    enum Slot { case home, search, flight }

    let allTags: [Tag]
    let slot: Slot
    var selectedTypes: Set<FileType> = []
    var selectedTagID: UUID? = nil
    var onToggleType: ((FileType) -> Void)? = nil
    var onToggleTag: ((Tag) -> Void)? = nil
    var onSearch: (Set<FileType>, Tag?) -> Void = { _, _ in }

    @Environment(DiscoveryChipsFlight.self) private var flight: DiscoveryChipsFlight?

    /// Home keeps the row short; Search needs every tag reachable.
    private var visibleTags: [Tag] {
        slot == .search ? allTags : Array(allTags.prefix(20))
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            typeRow
            if !allTags.isEmpty {
                tagRow
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            flight?.report(frame, for: slot)
        }
        // The flying copy stands in for these rows until it lands on them.
        .opacity(slot == .search && flight?.isActive == true ? 0 : 1)
    }

    private var typeRow: some View {
        DriftingFilterRow(direction: 1, rowID: 0, flight: flight) {
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(FileType.allCases.filter { $0 != .other }, id: \.self) { type in
                    let isSelected = selectedTypes.contains(type)
                    Button {
                        if let onToggleType { onToggleType(type) } else { onSearch([type], nil) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isSelected ? "checkmark" : type.sfSymbol)
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
                        .background(type.tintColor.opacity(isSelected ? 0.24 : 0.08), in: Capsule())
                        // Opaque backing: in Search the rows float over the results.
                        .background(AppTheme.Colors.groupedBG, in: Capsule())
                        .overlay(Capsule().strokeBorder(isSelected ? type.tintColor : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, AppTheme.Spacing.base)
        }
    }

    private var tagRow: some View {
        DriftingFilterRow(direction: -1, rowID: 1, flight: flight) {
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(visibleTags) { tag in
                    Button {
                        if let onToggleTag { onToggleTag(tag) } else { onSearch([], tag) }
                    } label: {
                        tagPill(tag: tag)
                    }
                    .buttonStyle(.plain)
                }
                if allTags.count > visibleTags.count {
                    Text("+\(allTags.count - visibleTags.count) more")
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
        let isSelected = selectedTagID == tag.id
        let color = Color(hex: tag.colorHex)
        return HStack(spacing: 6) {
            Image(systemName: isSelected ? "checkmark" : tag.sfSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
            Text(tag.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.Colors.label)
            Text("\(tag.totalItemCount)")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(color.opacity(isSelected ? 0.24 : 0.08), in: Capsule())
        .background(AppTheme.Colors.groupedBG, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(isSelected ? 1 : 0.18), lineWidth: 1))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Home → Search chip flight

/// Carries the chip rows from their place on Home to their place on Search.
/// The two tabs are separate view trees, so a copy drawn above the tab view makes the
/// trip, and every copy shares its drift offset so the chips never jump sideways.
@MainActor
@Observable
final class DiscoveryChipsFlight {
    struct RowState {
        var offset: CGFloat = 0
        var cycleWidth: CGFloat = 0
        var viewportWidth: CGFloat = 0
    }

    private(set) var isActive = false
    private(set) var frame: CGRect = .zero
    private(set) var selectedTypes: Set<FileType> = []
    private(set) var selectedTagID: UUID?

    // Written every frame while scrolling or drifting; nothing should re-render for them.
    @ObservationIgnored var rows: [Int: RowState] = [:]
    @ObservationIgnored private var homeFrame: CGRect = .zero
    @ObservationIgnored private var searchFrame: CGRect = .zero
    @ObservationIgnored private var hasLaunched = false
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let travel = Animation.spring(duration: 0.45, bounce: 0.12)

    func report(_ rect: CGRect, for slot: HomeDiscoveryChips.Slot) {
        guard rect.width > 0, rect.height > 0 else { return }
        switch slot {
        case .home:
            homeFrame = rect
        case .search:
            guard rect != searchFrame else { return }
            searchFrame = rect
            // The keyboard keeps moving the destination; follow it.
            if isActive && hasLaunched {
                withAnimation(Self.travel) { frame = rect }
            }
        case .flight:
            break
        }
    }

    func begin(selectedTypes: Set<FileType> = [], selectedTagID: UUID? = nil) {
        guard !isActive, homeFrame != .zero else { return }
        self.selectedTypes = selectedTypes
        self.selectedTagID = selectedTagID
        frame = homeFrame
        hasLaunched = false
        isActive = true
        task?.cancel()
        task = Task {
            // One beat for Search to lay out and report where the rows land.
            try? await Task.sleep(for: .milliseconds(40))
            hasLaunched = true
            if searchFrame != .zero {
                withAnimation(Self.travel) { frame = searchFrame }
            }
            try? await Task.sleep(for: .milliseconds(650))
            isActive = false
        }
    }
}

/// The copy of the rows that makes the trip. Lives above the tab view.
struct DiscoveryChipsFlightOverlay: View {
    @Environment(DiscoveryChipsFlight.self) private var flight
    @Query(sort: \Tag.name) private var allTags: [Tag]

    var body: some View {
        GeometryReader { proxy in
            if flight.isActive {
                HomeDiscoveryChips(
                    allTags: allTags,
                    slot: .flight,
                    selectedTypes: flight.selectedTypes,
                    selectedTagID: flight.selectedTagID
                )
                .frame(width: flight.frame.width)
                // Rows scrolled below the fold rise from the bottom edge instead.
                .offset(x: flight.frame.minX, y: min(flight.frame.minY, proxy.size.height))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// Keep the native scroll view and buttons so users can take over at any time.
private struct DriftingFilterRow<Content: View>: View {
    let direction: CGFloat
    let rowID: Int
    let flight: DiscoveryChipsFlight?
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @State private var position: ScrollPosition
    @State private var cycleWidth: CGFloat
    @State private var viewportWidth: CGFloat
    @State private var offset: CGFloat
    @State private var visible = false
    @State private var userControlled = false

    init(direction: CGFloat, rowID: Int, flight: DiscoveryChipsFlight?, @ViewBuilder content: () -> Content) {
        self.direction = direction
        self.rowID = rowID
        self.flight = flight
        self.content = content()
        // Start where the other copies of this row already are, so a copy that
        // appears mid-drift (the flying one, or Search's) lines up from its first frame.
        let seed = flight?.rows[rowID] ?? .init()
        _position = State(initialValue: ScrollPosition(x: seed.offset))
        _cycleWidth = State(initialValue: seed.cycleWidth)
        _viewportWidth = State(initialValue: seed.viewportWidth)
        _offset = State(initialValue: seed.offset)
    }

    private var repeats: Bool {
        !reduceMotion && !voiceOver && cycleWidth > viewportWidth && viewportWidth > 0
    }

    private var paused: Bool {
        !repeats || !visible || userControlled || scenePhase != .active
    }

    /// The shared drift position, folded into the middle copy of the content.
    private var sharedOffset: CGFloat {
        guard cycleWidth > 0 else { return 0 }
        let saved = max(flight?.rows[rowID]?.offset ?? 0, 0)
        return cycleWidth + saved.truncatingRemainder(dividingBy: cycleWidth)
    }

    private func share(_ x: CGFloat) {
        flight?.rows[rowID] = .init(offset: x, cycleWidth: cycleWidth, viewportWidth: viewportWidth)
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
            // Search hosts these rows in a safe-area inset, outside a vertical scroll view,
            // where scroll-visibility callbacks alone don't fire.
            .onAppear { visible = true }
            .onDisappear {
                visible = false
                userControlled = false
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.width } action: { _, width in
                viewportWidth = width
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                // Remember where the user left the row so the other copies match it.
                if userControlled && repeats { share(x) }
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
                offset = enabled ? sharedOffset : 0
                position.scrollTo(x: offset)
            }
            .onChange(of: visible) { _, isVisible in
                if isVisible && repeats {
                    offset = sharedOffset
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
                share(offset)
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
        .background(AppTheme.Colors.flatCard, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
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
