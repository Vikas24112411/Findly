import Foundation
import SwiftUI
import SwiftData

// Broadcast when ALL vault data (items, tags, history) is wiped from the store.
// Sent synchronously on the main thread BEFORE any await so that cached [Item]
// arrays in HomeViewModel / FilesViewModel are cleared before SwiftUI can re-render
// with stale references that would crash on deleted-object attribute access.
extension Notification.Name {
    static let vaultDataWiped = Notification.Name("FindlyVaultDataWiped")
    static let itemSaved = Notification.Name("FindlyItemSaved")
}

@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - Drive stats

    var driveUsedBytes: Int64 = 0
    var driveTotalBytes: Int64 = 0
    var isLoadingDriveStats: Bool = false

    // MARK: - Sync

    var autoSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "autoSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "autoSyncEnabled") }
    }

    var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }

    // MARK: - Theme

    var selectedTheme: AppearanceMode {
        get {
            AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "system") ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appearanceMode")
        }
    }

    enum AppearanceMode: String, CaseIterable {
        case light  = "light"
        case dark   = "dark"
        case system = "system"

        var displayName: String {
            switch self {
            case .light:  return "Light"
            case .dark:   return "Dark"
            case .system: return "System"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .light:  return .light
            case .dark:   return .dark
            case .system: return nil
            }
        }
    }

    // MARK: - Local storage

    var localStorageSize: Int64 = 0
    var isMigratingStorage = false
    var storageMigrationError: String?

    func loadLocalStorageSize(appContainer: AppContainer) async {
        localStorageSize = await appContainer.localStorage.sizeOfLocalStorage()
    }

    /// Copies all files to the new location and updates the stored preference.
    func migrateStorage(
        to location: StorageLocationService.Location,
        customURL: URL? = nil,
        appContainer: AppContainer
    ) async {
        isMigratingStorage = true
        defer { isMigratingStorage = false }

        do {
            guard let newBaseDir = StorageLocationService.shared.baseDirectory(for: location, customURL: customURL) else {
                throw StorageLocationError.missingCustomURL
            }
            let oldDir = try await appContainer.localStorage.migrateToDirectory(newBaseDir)
            try StorageLocationService.shared.setLocation(location, customURL: customURL)
            try? FileManager.default.removeItem(at: oldDir)
            await loadLocalStorageSize(appContainer: appContainer)
        } catch {
            storageMigrationError = error.localizedDescription
        }
    }

    // MARK: - Actions

    func loadDriveStats(appContainer: AppContainer) async {
        guard appContainer.auth.isAuthenticated else { return }
        isLoadingDriveStats = true
        defer { isLoadingDriveStats = false }
        do {
            let (used, total) = try await appContainer.drive.storageQuota()
            driveUsedBytes  = used
            driveTotalBytes = total
        } catch {
            // Non-critical — just don't show stats
        }
    }

    func manualSync(appContainer: AppContainer) async {
        await appContainer.sync.syncPendingItems()
        UserDefaults.standard.set(Date(), forKey: "lastSyncDate")
    }

    // MARK: - Operation progress (0.0 – 1.0)

    var exportProgress: Double = 0
    var importProgress: Double = 0

    // MARK: - Delete all data

    var isDeletingAll = false
    var deleteError: String?

    func deleteAllData(localStorage: LocalFileService, context: ModelContext) async {
        isDeletingAll = true
        defer { isDeletingAll = false }
        do {
            // Never stage the deletes on SwiftUI's live main context. Views and @Query
            // results can still hold lazy Item faults while Settings is presented; marking
            // those same instances as deleted detaches their backing data, and the next
            // render can crash while reading an attribute such as `fileType`.
            //
            // A sibling context performs the whole transaction without exposing that
            // intermediate deleted-object state to the view hierarchy. The main context
            // observes only the committed store change after save().
            let deletionContext = ModelContext(context.container)

            // Fetch + delete individually so SwiftData can nullify the Item↔Tag M2M
            // join entries first — context.delete(model:) is a SQL batch delete that
            // throws a "Constraint trigger violation" on that relationship.
            let items = try deletionContext.fetch(FetchDescriptor<Item>())
            items.forEach { deletionContext.delete($0) }
            let tags = try deletionContext.fetch(FetchDescriptor<Tag>())
            tags.forEach { deletionContext.delete($0) }
            let history = try deletionContext.fetch(FetchDescriptor<SearchHistoryEntry>())
            history.forEach { deletionContext.delete($0) }
            try deletionContext.save()
            // Synchronously clear any cached [Item] arrays in running view models BEFORE
            // the next await yields the main actor. Without this, SwiftUI would re-render
            // background views (Home, Files) whose view models still hold stale Item
            // references; those views crash accessing attribute faults on deleted objects.
            NotificationCenter.default.post(name: .vaultDataWiped, object: nil)
            // Only delete files after records are confirmed gone.
            try await localStorage.deleteAllFiles()
            localStorageSize = 0
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
