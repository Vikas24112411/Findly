import Foundation
import SwiftData

/// Bootstraps and vends the SwiftData `ModelContainer`.
///
/// Use `PersistenceController.shared` in production and
/// `PersistenceController(inMemory: true)` in tests / Xcode Previews.
final class PersistenceController: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = PersistenceController()

    /// An in-memory container suitable for SwiftUI Previews and unit tests.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        // Seed a few sample items for previews.
        let ctx = ModelContext(controller.container)
        let sampleTag = Tag(name: "Work", colorHex: "#3498DB", sfSymbol: "briefcase.fill")
        let sampleItem = Item(title: "Q4 Report.pdf", fileType: .pdf, fileSize: 2_048_000, originalFileName: "Q4_Report.pdf")
        sampleItem.tags = [sampleTag]
        sampleItem.syncStatus = .synced
        ctx.insert(sampleTag)
        ctx.insert(sampleItem)
        try? ctx.save()
        return controller
    }()

    // MARK: - Container

    let container: ModelContainer

    // MARK: - Init

    init(inMemory: Bool = false) {
        let schema = Schema([
            Item.self,
            Tag.self,
            SearchHistoryEntry.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData failed to create ModelContainer: \(error)")
        }
    }
}
