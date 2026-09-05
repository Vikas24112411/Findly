import Foundation
import SwiftData

struct TagHeatCell: Identifiable {
    let id = UUID()
    let tagName: String
    let tagColor: String
    let month: Date
    let count: Int
}

struct ActivityDay: Identifiable {
    var id: Date { date }
    let date: Date
    let added: Int
    let opened: Int
}

// MARK: - Activity range (session-only selection in the view)

enum ActivityRange: String, CaseIterable, Identifiable {
    case week7d, month30d, year12m

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week7d:   return "Last 7 Days"
        case .month30d: return "Last 30 Days"
        case .year12m:  return "Last 12 Months"
        }
    }

    var shortTitle: String {
        switch self {
        case .week7d:   return "7D"
        case .month30d: return "30D"
        case .year12m:  return "12M"
        }
    }

    var footnote: String {
        switch self {
        case .year12m:  return "Weekly buckets. Opens = distinct files last opened that week."
        default:        return "Opens = distinct files last opened that day."
        }
    }
}

@Observable
@MainActor
final class InsightsViewModel {

    // MARK: - Summary stats

    var totalItems: Int = 0
    var totalTags: Int  = 0
    var totalStorageBytes: Int64 = 0
    var pendingSyncCount: Int = 0

    // MARK: - File type distribution

    var fileTypeDistribution: [(type: FileType, count: Int)] = []

    // MARK: - Most used tags

    var topTags: [(tag: Tag, count: Int)] = []

    // MARK: - Most opened files

    var mostOpenedItems: [Item] = []

    // MARK: - Largest files

    var largestItems: [Item] = []

    // MARK: - Hygiene (needs attention)

    static let staleThresholdDays = 90
    static let hygieneListLimit = 20

    var untaggedItems: [Item] = []
    var neverOpenedItems: [Item] = []
    var staleItems: [Item] = []
    var untaggedCount: Int = 0
    var neverOpenedCount: Int = 0
    var staleCount: Int = 0

    var hygieneIsTidy: Bool {
        untaggedCount == 0 && neverOpenedCount == 0 && staleCount == 0
    }

    // MARK: - Recent uploads (by day)

    var recentlyAdded: [Item] = []

    // MARK: - Activity this week (last 7 days, legacy — kept for rollback)

    var weeklyActivity: [(day: String, count: Int)] = []

    // MARK: - Activity trend (added vs opened: 7d / 30d daily, 12m weekly buckets)

    var activityTrend7d: [ActivityDay] = []
    var activityTrend30d: [ActivityDay] = []
    var activityTrend12m: [ActivityDay] = []

    // MARK: - Storage growth over time

    var storageGrowth: [(month: Date, cumulativeBytes: Int64)] = []

    // MARK: - File type breakdown by size

    var fileTypeSizeDistribution: [(type: FileType, bytes: Int64)] = []

    // MARK: - Tag usage heatmap (top 6 tags × last 6 months)

    var tagHeatmap: [TagHeatCell] = []

    // MARK: - Context

    private var context: ModelContext?

    func activityTrend(for range: ActivityRange) -> [ActivityDay] {
        switch range {
        case .week7d:   return activityTrend7d
        case .month30d: return activityTrend30d
        case .year12m:  return activityTrend12m
        }
    }

    // Shared DateFormatter — allocated once instead of on every loadAll() call.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    func setup(context: ModelContext) {
        self.context = context
        Task { await loadAll() }
    }

    func loadAll() async {
        guard let context else { return }
        let allItems = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let allTags  = (try? context.fetch(FetchDescriptor<Tag>())) ?? []

        totalItems        = allItems.count
        totalTags         = allTags.count
        totalStorageBytes = allItems.reduce(0) { $0 + $1.fileSize }
        pendingSyncCount  = allItems.filter { $0.syncStatus.needsUpload }.count

        // File type distribution
        let grouped = Dictionary(grouping: allItems, by: \.fileType)
        fileTypeDistribution = FileType.allCases.compactMap { ft in
            let count = grouped[ft]?.count ?? 0
            return count > 0 ? (ft, count) : nil
        }.sorted { $0.count > $1.count }

        // Yield so other UI updates can run before the next batch of computation.
        await Task.yield()

        // Top tags by item count — build a flat count map (O(I×T)) instead of recursive traversal
        var tagItemCounts: [UUID: Int] = [:]
        for item in allItems {
            for tag in item.tags { tagItemCounts[tag.id, default: 0] += 1 }
        }
        topTags = allTags
            .map { ($0, tagItemCounts[$0.id] ?? 0) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(10)
            .map { $0 }

        // Most opened
        mostOpenedItems = allItems
            .filter { $0.viewCount > 0 }
            .sorted { $0.viewCount > $1.viewCount }
            .prefix(5)
            .map { $0 }

        // Largest files
        largestItems = allItems
            .sorted { $0.fileSize > $1.fileSize }
            .prefix(5)
            .map { $0 }

        // Hygiene — Untagged and Never opened may overlap (a file can be both);
        // each action (tagging, opening) monotonically lowers its own count.
        // Stale is disjoint from Never opened by construction (viewCount > 0).
        let staleCutoff = Calendar.current.date(
            byAdding: .day, value: -Self.staleThresholdDays, to: Date()
        ) ?? Date.distantPast
        let untagged = allItems.filter { $0.tags.isEmpty }
        let neverOpened = allItems.filter { $0.viewCount == 0 }
        let stale = allItems.filter { item in
            guard item.viewCount > 0, let lastOpened = item.lastOpenedAt else { return false }
            return lastOpened < staleCutoff
        }
        untaggedCount = untagged.count
        neverOpenedCount = neverOpened.count
        staleCount = stale.count
        untaggedItems = Array(untagged.prefix(Self.hygieneListLimit))
        neverOpenedItems = Array(neverOpened.sorted { $0.createdAt > $1.createdAt }.prefix(Self.hygieneListLimit))
        staleItems = Array(stale.sorted {
            ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast)
        }.prefix(Self.hygieneListLimit))

        // Recently added
        recentlyAdded = allItems
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20)
            .map { $0 }

        await Task.yield()

        // Activity: files added per day over the last 7 days (legacy).
        // Single O(n) grouping pass replaces the previous 7 × O(n) filter loop.
        let calendar = Calendar.current
        let today = Date()
        let itemsByDay = Dictionary(grouping: allItems) { calendar.startOfDay(for: $0.createdAt) }
        weeklyActivity = (0..<7).reversed().compactMap { daysAgo -> (String, Int)? in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return nil }
            let day = calendar.startOfDay(for: date)
            return (Self.dayFormatter.string(from: date), itemsByDay[day]?.count ?? 0)
        }

        // Activity trends: added (createdAt) vs opened (lastOpenedAt).
        // Note: opens = distinct items last opened that day/week (we track lastOpenedAt,
        // not a full open-event history), so repeat opens of one file count once.
        // 7d + 30d are daily buckets; 12m uses 52 weekly buckets (daily x 365 is
        // unreadable and slow). Single O(n) passes per dimension.
        let todayStart = calendar.startOfDay(for: today)
        var openedByDay: [Date: Int] = [:]
        var addedByWeek: [Date: Int] = [:]
        var openedByWeek: [Date: Int] = [:]
        // Week-start helper (startOfDay of the week's first day).
        func weekStart(for date: Date) -> Date? {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
            return calendar.startOfDay(for: interval.start)
        }
        guard let thisWeekStart = weekStart(for: todayStart) else { return }
        for item in allItems {
            // Weekly added bucket.
            if let ws = weekStart(for: item.createdAt),
               let weeksAgo = calendar.dateComponents([.weekOfYear], from: ws, to: thisWeekStart).weekOfYear,
               weeksAgo >= 0, weeksAgo < 52 {
                addedByWeek[ws, default: 0] += 1
            }
            guard let lastOpened = item.lastOpenedAt else { continue }
            let openDay = calendar.startOfDay(for: lastOpened)
            if let daysSince = calendar.dateComponents([.day], from: openDay, to: todayStart).day,
               daysSince >= 0, daysSince < 30 {
                openedByDay[openDay, default: 0] += 1
            }
            if let ws = weekStart(for: lastOpened),
               let weeksAgo = calendar.dateComponents([.weekOfYear], from: ws, to: thisWeekStart).weekOfYear,
               weeksAgo >= 0, weeksAgo < 52 {
                openedByWeek[ws, default: 0] += 1
            }
        }
        activityTrend7d = (0..<7).reversed().compactMap { daysAgo -> ActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: todayStart) else { return nil }
            return ActivityDay(
                date: date,
                added: itemsByDay[date]?.count ?? 0,
                opened: openedByDay[date] ?? 0
            )
        }
        activityTrend30d = (0..<30).reversed().compactMap { daysAgo -> ActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: todayStart) else { return nil }
            return ActivityDay(
                date: date,
                added: itemsByDay[date]?.count ?? 0,
                opened: openedByDay[date] ?? 0
            )
        }
        activityTrend12m = (0..<52).reversed().compactMap { weeksAgo -> ActivityDay? in
            guard let date = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeekStart) else { return nil }
            return ActivityDay(
                date: date,
                added: addedByWeek[date] ?? 0,
                opened: openedByWeek[date] ?? 0
            )
        }

        // Storage growth — cumulative vault size by month
        var monthlySizes: [Date: Int64] = [:]
        for item in allItems {
            guard let start = calendar.dateInterval(of: .month, for: item.createdAt)?.start else { continue }
            monthlySizes[start, default: 0] += item.fileSize
        }
        var running: Int64 = 0
        storageGrowth = monthlySizes.keys.sorted().map { month in
            running += monthlySizes[month, default: 0]
            return (month: month, cumulativeBytes: running)
        }

        // File type size distribution
        let sizeGrouped = Dictionary(grouping: allItems, by: \.fileType)
        fileTypeSizeDistribution = FileType.allCases.compactMap { ft in
            let bytes = sizeGrouped[ft]?.reduce(0) { $0 + $1.fileSize } ?? 0
            return bytes > 0 ? (ft, bytes) : nil
        }.sorted { $0.bytes > $1.bytes }

        await Task.yield()

        // Tag heatmap — top 6 tags × last 6 months
        let heatTagSet = Set(topTags.prefix(6).map { $0.tag.id })
        let heatTags   = topTags.prefix(6).map { $0.tag }
        guard let currentMonthStart = calendar.dateInterval(of: .month, for: Date())?.start else { return }
        let heatMonths: [Date] = (0..<6).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: currentMonthStart)
        }
        var heatCounts: [UUID: [Date: Int]] = [:]
        for item in allItems {
            guard let monthStart = calendar.dateInterval(of: .month, for: item.createdAt)?.start else { continue }
            guard heatMonths.contains(monthStart) else { continue }
            for tag in item.tags where heatTagSet.contains(tag.id) {
                heatCounts[tag.id, default: [:]][monthStart, default: 0] += 1
            }
        }
        tagHeatmap = heatTags.flatMap { tag in
            heatMonths.map { month in
                TagHeatCell(
                    tagName: tag.name,
                    tagColor: tag.colorHex,
                    month: month,
                    count: heatCounts[tag.id]?[month] ?? 0
                )
            }
        }
    }
}
