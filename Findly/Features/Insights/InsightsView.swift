import SwiftUI
import Charts

struct InsightsView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = InsightsViewModel()
    @State private var scrollOffset: CGFloat = 0
    @AppStorage("insightsShowStorageGrowth") private var showStorageGrowth = true
    @AppStorage("insightsShowWeeklyActivity") private var showWeeklyActivity = true
    @AppStorage("insightsShowFileTypes") private var showFileTypes = true
    @AppStorage("insightsShowStorageByType") private var showStorageByType = true
    @AppStorage("insightsShowTopTags") private var showTopTags = true
    @AppStorage("insightsShowTagHeatmap") private var showTagHeatmap = true
    @AppStorage("insightsShowMostOpened") private var showMostOpened = true
    @AppStorage("insightsShowLargestFiles") private var showLargestFiles = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    LargeTitleHeader(title: "Insights", progress: scrollProgress(from: scrollOffset))
                    LazyVStack(spacing: AppTheme.Spacing.xLarge) {
                        summaryCards
                        if showStorageGrowth  && !viewModel.storageGrowth.isEmpty            { storageGrowthSection }
                        if showWeeklyActivity && !viewModel.weeklyActivity.isEmpty            { activitySection }
                        if showFileTypes      && !viewModel.fileTypeDistribution.isEmpty      { fileTypeChart }
                        if showStorageByType  && !viewModel.fileTypeSizeDistribution.isEmpty  { fileTypeSizeChart }
                        if showTopTags        && !viewModel.topTags.isEmpty                   { topTagsSection }
                        if showTagHeatmap     && !viewModel.tagHeatmap.isEmpty                { tagHeatmapSection }
                        if showMostOpened     && !viewModel.mostOpenedItems.isEmpty           { mostOpenedSection }
                        if showLargestFiles   && !viewModel.largestItems.isEmpty              { largestFilesSection }
                    }
                    .padding(.horizontal, AppTheme.Spacing.base)
                    .padding(.bottom, AppTheme.Spacing.large)
                }
            }
            .background(AppTheme.Colors.groupedBG)
            .trackScrollOffset($scrollOffset)
            .navTransitionTitle("Insights", progress: scrollProgress(from: scrollOffset))
            .onAppear {
                viewModel.setup(context: modelContext)
            }
            .refreshable {
                viewModel.loadAll()
            }
        }
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

    // MARK: - Activity this week

    private var activitySection: some View {
        insightCard(title: "Added This Week", symbol: "calendar") {
            Chart(viewModel.weeklyActivity, id: \.day) { entry in
                BarMark(
                    x: .value("Day", entry.day),
                    y: .value("Files", entry.count)
                )
                .foregroundStyle(
                    entry.count > 0
                        ? AppTheme.Colors.accent.gradient
                        : Color.secondary.opacity(0.2).gradient
                )
                .cornerRadius(5)
            }
            .frame(height: 90)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                }
            }
            .chartYAxis(.hidden)
            .chartXScale(range: .plotDimension(padding: 8))
        }
    }

    // MARK: - File type donut + legend

    private var fileTypeChart: some View {
        insightCard(title: "File Types", symbol: "square.grid.2x2.fill") {
            HStack(alignment: .center, spacing: AppTheme.Spacing.xLarge) {
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
                    ForEach(viewModel.fileTypeDistribution.prefix(6), id: \.type) { entry in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(entry.type.tintColor)
                                .frame(width: 10, height: 10)
                            Text(entry.type.displayName)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppTheme.Colors.label)
                            Spacer()
                            Text("\(entry.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    NavigationLink(destination: ItemDetailView(item: item)) {
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
                    NavigationLink(destination: ItemDetailView(item: item)) {
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

    // MARK: - Storage by file type (bytes)

    private var fileTypeSizeChart: some View {
        insightCard(title: "Storage by Type", symbol: "externaldrive.fill") {
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
    }

    // MARK: - Tag activity heatmap

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

#Preview {
    InsightsView()
        .modelContainer(PersistenceController.preview.container)
        .environment(AppContainer())
}
