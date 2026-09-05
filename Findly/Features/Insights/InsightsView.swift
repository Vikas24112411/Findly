import SwiftUI
import Charts

struct InsightsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(FileViewerCoordinator.self) private var fileViewer
    @State private var viewModel = InsightsViewModel()
    @State private var scrollOffset: CGFloat = 0
    @AppStorage("insightsShowStorageGrowth") private var showStorageGrowth = true
    @AppStorage("insightsShowWeeklyActivity") private var showWeeklyActivity = true
    @AppStorage("insightsShowBreakdownByType") private var showBreakdown = true
    @AppStorage("insightsShowHygiene") private var showHygiene = true
    @AppStorage("insightsShowTopTags") private var showTopTags = true
    @AppStorage("insightsShowMostOpened") private var showMostOpened = true
    @AppStorage("insightsShowLargestFiles") private var showLargestFiles = true
    @AppStorage("insightsBreakdownMode") private var breakdownMode = BreakdownMode.count
    // Legacy keys — kept for one-time migration, no longer rendered.
    // showTagHeatmap is hidden per redesign (kept for rollback, not rendered).
    @AppStorage("insightsShowFileTypes") private var legacyShowFileTypes = true
    @AppStorage("insightsShowStorageByType") private var legacyShowStorageByType = true
    @AppStorage("insightsShowTagHeatmap") private var legacyShowTagHeatmap = true
    @AppStorage("insightsBreakdownMigrated") private var breakdownMigrated = false
    @State private var selectedSection: InsightsSection = .overview
    @State private var activityRange = ActivityRange.month30d

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    LargeTitleHeader(title: "Insights", progress: scrollProgress(from: scrollOffset))
                    sectionPicker
                    LazyVStack(spacing: AppTheme.Spacing.xLarge) {
                        summaryCards
                        if showHygiene && selectedSection == .overview && viewModel.totalItems > 0 { hygieneSection }
                        sectionContent
                    }
                    .padding(.horizontal, AppTheme.Spacing.base)
                    .padding(.bottom, AppTheme.Spacing.large)
                    .padding(.top, AppTheme.Spacing.medium)
                }
            }
            .background(AppTheme.Colors.groupedBG)
            .trackScrollOffset($scrollOffset)
            .navTransitionTitle("Insights", progress: scrollProgress(from: scrollOffset))
            .onAppear {
                viewModel.setup(context: modelContext)
                migrateBreakdownToggle()
            }
            .refreshable {
                await viewModel.loadAll()
            }
        }
    }

    // MARK: - One-time migration: FileTypes + StorageByType -> Breakdown

    private func migrateBreakdownToggle() {
        guard !breakdownMigrated else { return }
        // Preserve opt-outs: only hide breakdown if both legacy toggles were off.
        showBreakdown = legacyShowFileTypes || legacyShowStorageByType
        _ = legacyShowTagHeatmap // retained for rollback, intentionally unrendered
        breakdownMigrated = true
    }

    // MARK: - Segmented hub (Option B, iOS 17-safe: Picker + ScrollView + Charts only)

    private var sectionPicker: some View {
        Picker("Insights section", selection: $selectedSection) {
            ForEach(InsightsSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppTheme.Spacing.base)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(AppTheme.Colors.groupedBG)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview:
            // Curated highlights: one card per domain, respects Settings toggles.
            if showWeeklyActivity && activityHasData                                 { activitySection }
            if showBreakdown && !breakdownIsEmpty                                 { breakdownByTypeSection }
            if showTopTags        && !viewModel.topTags.isEmpty                   { topTagsSection }
            if showMostOpened     && !viewModel.mostOpenedItems.isEmpty           { mostOpenedSection }
            if overviewIsEmpty {
                ContentUnavailableView(
                    "No Highlights",
                    systemImage: "chart.bar.fill",
                    description: Text("Add files or enable sections in Settings to see highlights.")
                )
            }
        case .storage:
            if showStorageGrowth  && !viewModel.storageGrowth.isEmpty            { storageGrowthSection }
            if showWeeklyActivity && activityHasData                              { activitySection }
            if showBreakdown && !breakdownIsEmpty                                 { breakdownByTypeSection }
            if storageIsEmpty {
                ContentUnavailableView(
                    "No Storage Insights",
                    systemImage: "internaldrive.fill",
                    description: Text("Enable Storage sections in Settings to see them here.")
                )
            }
        case .tags:
            if showTopTags    && !viewModel.topTags.isEmpty    { topTagsSection }
            // Tag heatmap hidden per redesign (tagHeatmapSection kept for rollback, not rendered).
            if tagsIsEmpty {
                ContentUnavailableView(
                    "No Tag Insights",
                    systemImage: "tag.fill",
                    description: Text("Tag some files or enable Tag sections in Settings.")
                )
            }
        case .files:
            if showMostOpened   && !viewModel.mostOpenedItems.isEmpty { mostOpenedSection }
            if showLargestFiles && !viewModel.largestItems.isEmpty    { largestFilesSection }
            if filesIsEmpty {
                ContentUnavailableView(
                    "No File Insights",
                    systemImage: "doc.fill",
                    description: Text("Open files or enable File sections in Settings.")
                )
            }
        }
    }

    private var activityHasData: Bool {
        viewModel.activityTrend(for: activityRange).contains { $0.added > 0 || $0.opened > 0 }
    }

    private var breakdownIsEmpty: Bool {
        viewModel.fileTypeDistribution.isEmpty && viewModel.fileTypeSizeDistribution.isEmpty
    }

    private var overviewIsEmpty: Bool {
        // Hygiene renders its own tidy state, so it only counts as empty in an empty vault.
        (showHygiene ? viewModel.totalItems == 0 : true)
            && (showWeeklyActivity ? !activityHasData : true)
            && (showBreakdown ? breakdownIsEmpty : true)
            && (showTopTags ? viewModel.topTags.isEmpty : true)
            && (showMostOpened ? viewModel.mostOpenedItems.isEmpty : true)
    }

    private var storageIsEmpty: Bool {
        (showStorageGrowth ? viewModel.storageGrowth.isEmpty : true)
            && (showWeeklyActivity ? !activityHasData : true)
            && (showBreakdown ? breakdownIsEmpty : true)
    }

    private var tagsIsEmpty: Bool {
        // Heatmap hidden — Tags tab is Top Tags only.
        (showTopTags ? viewModel.topTags.isEmpty : true)
    }

    private var filesIsEmpty: Bool {
        (showMostOpened ? viewModel.mostOpenedItems.isEmpty : true)
            && (showLargestFiles ? viewModel.largestItems.isEmpty : true)
    }

    // MARK: - Needs attention (hygiene to-do list)

    private var hygieneSection: some View {
        insightCard(title: "Needs Attention", symbol: "checklist") {
            if viewModel.hygieneIsTidy && viewModel.totalItems > 0 {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.syncSynced)
                    Text("All tidy — everything is tagged and recently opened.")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
                .padding(.vertical, AppTheme.Spacing.xSmall)
            } else {
                VStack(spacing: 0) {
                    hygieneRow(
                        title: "Untagged files",
                        subtitle: "Add tags to find them later",
                        count: viewModel.untaggedCount,
                        symbol: "tag.slash.fill",
                        tint: AppTheme.Colors.noteTint,
                        items: viewModel.untaggedItems
                    )
                    Divider().padding(.leading, 46)
                    hygieneRow(
                        title: "Never opened",
                        subtitle: "Open or remove what you don't need",
                        count: viewModel.neverOpenedCount,
                        symbol: "eye.slash.fill",
                        tint: AppTheme.Colors.accent,
                        items: viewModel.neverOpenedItems
                    )
                    Divider().padding(.leading, 46)
                    hygieneRow(
                        title: "Stale · 90+ days",
                        subtitle: "Not opened in the last 90 days",
                        count: viewModel.staleCount,
                        symbol: "clock.fill",
                        tint: AppTheme.Colors.syncPending,
                        items: viewModel.staleItems
                    )
                }
            }
        }
    }

    private func hygieneRow(
        title: String,
        subtitle: String,
        count: Int,
        symbol: String,
        tint: Color,
        items: [Item]
    ) -> some View {
        NavigationLink {
            HygieneListView(title: title, items: items, totalCount: count)
        } label: {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.label)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                }
                Spacer()
                Text("\(count)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.label)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.45 : 1.0)
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 0) {
            statCell("Total Files",
                     "\(viewModel.totalItems)",
                     "doc.fill",
                     AppTheme.Colors.accent)
            Divider().frame(height: 48)
            statCell("Tags",
                     "\(viewModel.totalTags)",
                     "tag.fill",
                     AppTheme.Colors.noteTint)
            Divider().frame(height: 48)
            statCell("Storage",
                     viewModel.totalStorageBytes.fileSizeString,
                     "internaldrive.fill",
                     AppTheme.Colors.videoTint)
            Divider().frame(height: 48)
            statCell("Pending Sync",
                     "\(viewModel.pendingSyncCount)",
                     viewModel.pendingSyncCount > 0 ? "clock.badge.exclamationmark.fill" : "checkmark.circle.fill",
                     viewModel.pendingSyncCount > 0 ? AppTheme.Colors.syncPending : AppTheme.Colors.syncSynced)
        }
        .padding(.vertical, AppTheme.Spacing.medium)
        .background(AppTheme.Colors.secondaryBG)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
    }

    private func statCell(_ title: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.label)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.small)
        .padding(.horizontal, 4)
    }

    // MARK: - Activity trend (7D / 30D daily, 12M weekly buckets)

    private var activitySection: some View {
        let trend = viewModel.activityTrend(for: activityRange)
        let totalAdded = trend.reduce(0) { $0 + $1.added }
        let totalOpened = trend.reduce(0) { $0 + $1.opened }
        return insightCard(title: "Activity · \(activityRange.title)", symbol: "calendar") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Picker("Activity range", selection: $activityRange) {
                    ForEach(ActivityRange.allCases) { range in
                        Text(range.shortTitle).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                HStack(spacing: AppTheme.Spacing.medium) {
                    legendDot(AppTheme.Colors.accent, "Added · \(totalAdded)")
                    legendDot(AppTheme.Colors.syncSynced, "Opened · \(totalOpened)")
                }
                Chart(trend) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: activityRange.unit),
                        y: .value("Added", day.added)
                    )
                    .foregroundStyle(AppTheme.Colors.accent.opacity(0.85))
                    .cornerRadius(2)
                    LineMark(
                        x: .value("Date", day.date, unit: activityRange.unit),
                        y: .value("Opened", day.opened)
                    )
                    .foregroundStyle(AppTheme.Colors.syncSynced)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(
                        x: .value("Date", day.date, unit: activityRange.unit),
                        y: .value("Opened", day.opened)
                    )
                    .foregroundStyle(AppTheme.Colors.syncSynced)
                    .symbolSize(12)
                }
                .frame(height: 120)
                .chartXAxis {
                    AxisMarks(values: activityRange.stride) { _ in
                        AxisValueLabel(format: activityRange.labelFormat, centered: true)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let n = value.as(Int.self) {
                                Text("\(n)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                            }
                        }
                    }
                }
                Text(activityRange.footnote)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
        }
    }

    // MARK: - Breakdown by type (merged: File Types count + Storage by Type size)

    private var breakdownByTypeSection: some View {
        insightCard(title: "Breakdown by Type", symbol: "square.grid.2x2.fill") {
            VStack(spacing: AppTheme.Spacing.medium) {
                Picker("Breakdown mode", selection: $breakdownMode) {
                    ForEach(BreakdownMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if breakdownMode == .count {
                    breakdownCountContent
                } else {
                    breakdownSizeContent
                }
            }
        }
    }

    private var breakdownCountContent: some View {
        let total = max(viewModel.fileTypeDistribution.reduce(0) { $0 + $1.count }, 1)
        return HStack(alignment: .center, spacing: AppTheme.Spacing.xLarge) {
            Chart(viewModel.fileTypeDistribution, id: \.type) { entry in
                SectorMark(
                    angle: .value("Count", entry.count),
                    innerRadius: .ratio(0.54),
                    angularInset: 2.5
                )
                .foregroundStyle(entry.type.tintColor)
                .cornerRadius(5)
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                ForEach(viewModel.fileTypeDistribution, id: \.type) { entry in
                    let pct = Int(round(Double(entry.count) / Double(total) * 100))
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(entry.type.tintColor)
                            .frame(width: 10, height: 10)
                        Text(entry.type.displayName)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppTheme.Colors.label)
                        Spacer()
                        Text("\(entry.count) · \(pct)%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var breakdownSizeContent: some View {
        Chart(viewModel.fileTypeSizeDistribution, id: \.type) { entry in
            BarMark(
                x: .value("Bytes", Double(entry.bytes) / 1_000_000.0),
                y: .value("Type", entry.type.displayName)
            )
            .foregroundStyle(entry.type.tintColor)
            .cornerRadius(4)
            .annotation(position: .trailing, alignment: .leading) {
                Text(entry.bytes.fileSizeString)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
        }
        .frame(height: CGFloat(viewModel.fileTypeSizeDistribution.count) * 30 + 10)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Colors.label)
            }
        }
    }

    // MARK: - Top tags with progress bars

    private var topTagsSection: some View {
        let maxCount = max(viewModel.topTags.first?.count ?? 1, 1)
        return insightCard(title: "Top Tags", symbol: "tag.fill") {
            VStack(spacing: AppTheme.Spacing.medium) {
                ForEach(viewModel.topTags.prefix(5), id: \.tag.id) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            TagSymbolView(sfSymbol: entry.tag.sfSymbol, color: Color(hex: entry.tag.colorHex), size: 12)
                            Text(entry.tag.name)
                                .font(AppTheme.Typography.subheadline)
                                .foregroundStyle(AppTheme.Colors.label)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.count) file\(entry.count == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(hex: entry.tag.colorHex).opacity(0.12))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(Color(hex: entry.tag.colorHex))
                                    .frame(
                                        width: geo.size.width * CGFloat(entry.count) / CGFloat(maxCount),
                                        height: 5
                                    )
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
    }

    // MARK: - Most opened

    private var mostOpenedSection: some View {
        insightCard(title: "Most Opened", symbol: "flame.fill") {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.mostOpenedItems.enumerated()), id: \.element.id) { index, item in
                    Button { fileViewer.open(item) } label: {
                        HStack(spacing: AppTheme.Spacing.medium) {
                            // Rank
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(index == 0 ? AppTheme.Colors.accent : AppTheme.Colors.tertiaryLabel)
                                .frame(width: 18, alignment: .center)

                            // Icon
                            Image(systemName: item.fileType.sfSymbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(item.fileType.tintColor)
                                .frame(width: 30, height: 30)
                                .background(item.fileType.tintColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            Text(item.title)
                                .font(AppTheme.Typography.subheadline)
                                .foregroundStyle(AppTheme.Colors.label)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.viewCount)×")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if index < viewModel.mostOpenedItems.count - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
            }
        }
    }

    // MARK: - Largest files

    private var largestFilesSection: some View {
        insightCard(title: "Largest Files", symbol: "archivebox.fill") {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.largestItems.enumerated()), id: \.element.id) { index, item in
                    Button { fileViewer.open(item) } label: {
                        HStack(spacing: AppTheme.Spacing.medium) {
                            Image(systemName: item.fileType.sfSymbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(item.fileType.tintColor)
                                .frame(width: 30, height: 30)
                                .background(item.fileType.tintColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            Text(item.title)
                                .font(AppTheme.Typography.subheadline)
                                .foregroundStyle(AppTheme.Colors.label)
                                .lineLimit(1)
                            Spacer()
                            Text(item.fileSize.fileSizeString)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if index < viewModel.largestItems.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
    }

    // MARK: - Storage growth

    private var storageGrowthSection: some View {
        insightCard(title: "Storage Growth", symbol: "chart.line.uptrend.xyaxis") {
            Chart(viewModel.storageGrowth, id: \.month) { point in
                AreaMark(
                    x: .value("Month", point.month, unit: .month),
                    y: .value("MB", Double(point.cumulativeBytes) / 1_000_000.0)
                )
                .foregroundStyle(AppTheme.Colors.videoTint.opacity(0.15))
                LineMark(
                    x: .value("Month", point.month, unit: .month),
                    y: .value("MB", Double(point.cumulativeBytes) / 1_000_000.0)
                )
                .foregroundStyle(AppTheme.Colors.videoTint)
                .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(
                    x: .value("Month", point.month, unit: .month),
                    y: .value("MB", Double(point.cumulativeBytes) / 1_000_000.0)
                )
                .foregroundStyle(AppTheme.Colors.videoTint)
                .symbolSize(25)
            }
            .frame(height: 110)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let mb = value.as(Double.self) {
                            Text(mb >= 1000 ? "\(Int(mb / 1000))GB" : "\(Int(mb))MB")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tag activity heatmap (HIDDEN per redesign — kept for rollback, not rendered)

    private var tagHeatmapSection: some View {
        let maxCount = viewModel.tagHeatmap.map(\.count).max() ?? 1
        let tagCount = Set(viewModel.tagHeatmap.map(\.tagName)).count
        return insightCard(title: "Tag Activity", symbol: "chart.bar.doc.horizontal") {
            Chart(viewModel.tagHeatmap) { cell in
                RectangleMark(
                    x: .value("Month", cell.month, unit: .month),
                    y: .value("Tag", cell.tagName)
                )
                .foregroundStyle(
                    Color(hex: cell.tagColor)
                        .opacity(cell.count == 0 ? 0.06 : 0.15 + 0.85 * Double(cell.count) / Double(maxCount))
                )
                .cornerRadius(3)
            }
            .frame(height: CGFloat(tagCount) * 28 + 20)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.Colors.label)
                }
            }
        }
    }

    // MARK: - Card container

    private func insightCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                Text(title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.label)
            }
            content()
        }
        .padding(AppTheme.Spacing.base)
        .background(AppTheme.Colors.secondaryBG)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
    }
}

// MARK: - Segmented sections (iOS 17-compatible, no iOS 18+ APIs)

enum InsightsSection: String, CaseIterable, Identifiable {
    case overview, storage, tags, files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .storage:  return "Storage"
        case .tags:     return "Tags"
        case .files:    return "Files"
        }
    }
}

// MARK: - Breakdown mode (persisted via @AppStorage, iOS 17-safe)

enum BreakdownMode: String, CaseIterable, Identifiable {
    case count, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .count: return "Count"
        case .size:  return "Size"
        }
    }
}

// MARK: - Activity range chart config (iOS 16+ Charts APIs only)

extension ActivityRange {
    var unit: Calendar.Component {
        switch self {
        case .week7d, .month30d: return .day
        case .year12m:            return .weekOfYear
        }
    }

    var stride: AxisMarkValues {
        switch self {
        case .week7d:   return .stride(by: .day, count: 1)
        case .month30d: return .stride(by: .day, count: 7)
        case .year12m:  return .stride(by: .month, count: 2)
        }
    }

    var labelFormat: Date.FormatStyle {
        switch self {
        case .week7d:   return .dateTime.weekday(.abbreviated)
        case .month30d: return .dateTime.day().month(.abbreviated)
        case .year12m:  return .dateTime.month(.abbreviated)
        }
    }
}

#Preview {
    InsightsView()
        .modelContainer(PersistenceController.preview.container)
        .environment(AppContainer())
        .environment(FileViewerCoordinator())
}
