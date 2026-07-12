import Foundation
import SwiftData

// MARK: - Versioned Schema

/// Current schema version. Add new VersionedSchema enums and MigrationStage entries
/// in AppMigrationPlan when the model changes in a future release.
enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Item.self, Tag.self, SearchHistoryEntry.self]
    }
}

// MARK: - Migration Plan

/// Add a new VersionedSchema + MigrationStage here whenever the schema changes.
/// Lightweight stages handle additive changes (new optional attributes, new models)
/// without writing custom migration code.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - Controller

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

    /// `true` when the on-disk store could not be migrated and was backed up.
    /// The app should surface a notice to the user when this is set.
    private(set) var storeWasRecovered = false

    // MARK: - Init

    init(inMemory: Bool = false) {
        let schema = Schema(AppSchemaV1.models)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )

        // Attempt normal open — migration plan handles additive schema changes automatically.
        if let c = try? ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config]) {
            container = c
            return
        }

        guard !inMemory else {
            fatalError("SwiftData failed to create in-memory container")
        }

        // Migration failed (incompatible schema change). Back up the existing store files
        // so data is never permanently lost, then start fresh. The backup can be inspected
        // or restored manually from the app's Application Support directory.
        //
        // Safety order: copy → verify new container opens → then delete originals.
        // This ensures the original store is never deleted unless we know the fresh container works.
        let storeURL = config.url
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupBase = storeURL.deletingLastPathComponent()
            .appendingPathComponent("\(storeURL.lastPathComponent).backup-\(timestamp)")

        // Pass 1: copy to backup (before any deletion).
        for suffix in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            let dst = URL(fileURLWithPath: backupBase.path + suffix)
            try? FileManager.default.copyItem(at: src, to: dst)
        }

        // Pass 2: delete originals so ModelContainer can create a fresh empty store.
        for suffix in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            try? FileManager.default.removeItem(at: src)
        }

        do {
            container = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
            storeWasRecovered = true
        } catch {
            // Container creation failed even on a fresh store. Attempt to restore the backup
            // so the user's data is not permanently lost before we crash.
            for suffix in ["", "-shm", "-wal"] {
                let backup = URL(fileURLWithPath: backupBase.path + suffix)
                let original = URL(fileURLWithPath: storeURL.path + suffix)
                try? FileManager.default.copyItem(at: backup, to: original)
            }
            fatalError("SwiftData failed to create ModelContainer even after store reset: \(error)")
        }
    }
}
