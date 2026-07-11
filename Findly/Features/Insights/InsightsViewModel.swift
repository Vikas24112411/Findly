import Foundation
import SwiftData

struct TagHeatCell: Identifiable {
    let id = UUID()
    let tagName: String
    let tagColor: String
    let month: Date
    let count: Int
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

    // MARK: - Recent uploads (by day)

    var recentlyAdded: [Item] = []

    // MARK: - Activity this week (last 7 days)

    var weeklyActivity: [(day: String, count: Int)] = []

    // MARK: - Storage growth over time

    var storageGrowth: [(month: Date, cumulativeBytes: Int64)] = []

    // MARK: - File type breakdown by size

    var fileTypeSizeDistribution: [(type: FileType, bytes: Int64)] = []

    // MARK: - Tag usage heatmap (top 6 tags × last 6 months)

    var tagHeatmap: [TagHeatCell] = []

    // MARK: - Context

    private var context: ModelContext?

    func setup(context: ModelContext) {
        self.context = context
        loadAll()
    }

    func loadAll() {
        guard let context else { return }
        let allItems = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let allTags  = (try? context.fetch(FetchDescriptor<Tag>())) ?? []

        totalItems        = allItems.count
        totalTags         = allTags.count
        totalStorageBytes = allItems.reduce(0) { $0 + $1.fileSize }
        pendingSyncCount  = allItems.filter { $0.syncStatus.needsRetry }.count

        // File type distribution
        let grouped = Dictionary(grouping: allItems, by: \.fileType)
        fileTypeDistribution = FileType.allCases.compactMap { ft in
            let count = grouped[ft]?.count ?? 0
            return count > 0 ? (ft, count) : nil
        }.sorted { $0.count > $1.count }

        // Top tags by item count
        topTags = allTags
            .map { ($0, $0.totalItemCount) }
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

        // Recently added
        recentlyAdded = allItems
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20)
            .map { $0 }

        // Activity: files added per day over the last 7 days
        let calendar = Calendar.current
        let today = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        weeklyActivity = (0..<7).reversed().map { daysAgo -> (String, Int) in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let label = dayFormatter.string(from: date)
            let count = allItems.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }.count
            return (label, count)
        }

        // Storage growth — cumulative vault size by month
        var monthlySizes: [Date: Int64] = [:]
        for item in allItems {
            let start = calendar.dateInterval(of: .month, for: item.createdAt)!.start
            monthlySizes[start, default: 0] += item.fileSize
        }
        var running: Int64 = 0
        storageGrowth = monthlySizes.keys.sorted().map { month in
            running += monthlySizes[month]!
            return (month: month, cumulativeBytes: running)
        }

        // File type size distribution
        let sizeGrouped = Dictionary(grouping: allItems, by: \.fileType)
        fileTypeSizeDistribution = FileType.allCases.compactMap { ft in
            let bytes = sizeGrouped[ft]?.reduce(0) { $0 + $1.fileSize } ?? 0
            return bytes > 0 ? (ft, bytes) : nil
        }.sorted { $0.bytes > $1.bytes }

        // Tag heatmap — top 6 tags × last 6 months
        let heatTagSet = Set(topTags.prefix(6).map { $0.tag.id })
        let heatTags   = topTags.prefix(6).map { $0.tag }
        let currentMonthStart = calendar.dateInterval(of: .month, for: Date())!.start
        let heatMonths: [Date] = (0..<6).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: currentMonthStart)
        }
        var heatCounts: [UUID: [Date: Int]] = [:]
        for item in allItems {
            let monthStart = calendar.dateInterval(of: .month, for: item.createdAt)!.start
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
