import Foundation
import SwiftData

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
    }
}
