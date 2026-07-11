import Foundation
import SwiftData

@Model
final class SearchHistoryEntry {

    @Attribute(.unique)
    var id: UUID

    var query: String
    var timestamp: Date

    /// Number of times this query has been executed.
    var useCount: Int

    init(query: String) {
        self.id = UUID()
        self.query = query
        self.timestamp = Date()
        self.useCount = 1
    }

    func recordUse() {
        useCount += 1
        timestamp = Date()
    }
}
