import Foundation
import SwiftData

/// Dependency injection root.
///
/// Construct once in `FindlyApp` and inject via `.environment(appContainer)`.
/// All services are initialized here so they share the same instances throughout the app.
@Observable
@MainActor
final class AppContainer {

    // MARK: - Persistence

    let persistence: PersistenceController

    // MARK: - Services

    let auth: AuthService
    let drive: GoogleDriveService
    let localStorage: LocalFileService
    let sync: SyncService
    let tokenRefresher: TokenRefresher
    let export = ExportService()
    let importService = ImportService()
    private let shareImporter = ShareInboxImporter()
    var shareImportError: String?

    func publishShareCatalog() async {
        UserDefaults(suiteName: ShareInbox.groupID)?.set(UserDefaults.standard.bool(forKey: "appLockEnabled"), forKey: "appLockEnabled")
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"),
              let inbox = try? ShareInbox() else { return }
        do {
            let tags = try persistence.container.mainContext.fetch(FetchDescriptor<Tag>())
            let catalog = ShareCatalog(
                tags: tags.map { SharedTag(id: $0.id, name: $0.name, colorHex: $0.colorHex, sfSymbol: $0.sfSymbol) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                requiresUnlock: UserDefaults.standard.bool(forKey: "appLockEnabled"),
                appearanceMode: UserDefaults.standard.string(forKey: "appearanceMode")
            )
            try await Task.detached { try inbox.publish(catalog) }.value
        } catch {
            // Sharing will report an unavailable catalog; the main vault remains usable.
        }
    }

    func receiveSharedFiles() async {
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"),
              let inbox = try? ShareInbox() else { return }
        do {
            _ = try await shareImporter.importFiles(inbox: inbox, container: persistence.container,
                                                    storage: localStorage, authenticated: auth.isAuthenticated)
            shareImportError = nil
        } catch {
            shareImportError = "A shared file couldn’t be added to your vault. It is still saved and will be retried when you open Findly again. " + error.localizedDescription
        }
        await publishShareCatalog()
    }
    let periodicBackup: PeriodicBackupService

    /// App-wide experimental feature flags. Owned here and injected into
    /// SwiftUI alongside the container so consumers update immediately.
    /// Local-only (`UserDefaults`), never synced through Google Drive.
    let experimentalFeatures = ExperimentalFeatureStore()

    // MARK: - Init

    /// Designated init — takes pre-resolved values so heavy IO can be done off the main thread.
    init(persistence: PersistenceController, baseDirectory: URL) {
        self.persistence = persistence
        auth           = AuthService()
        drive          = GoogleDriveService(auth: auth)
        tokenRefresher = TokenRefresher.shared

        guard let localFS = try? LocalFileService(baseDirectory: baseDirectory) else {
            fatalError("Could not initialize local file storage.")
        }
        localStorage = localFS

        sync = SyncService(
            drive: drive,
            auth: auth,
            localStorage: localStorage,
            context: persistence.container.mainContext
        )

        periodicBackup = PeriodicBackupService(
            exportService: export,
            localStorage: localStorage,
            modelContainer: persistence.container
        )

        BackgroundSyncTask.register(syncService: sync)
        BackgroundBackupTask.register(service: periodicBackup)
    }

    /// Async factory — runs the two blocking operations (SQLite open + bookmark resolution)
    /// on a detached task so the main RunLoop stays free during startup.
    static func makeAsync() async -> AppContainer {
        let (persistence, baseDir) = await Task.detached(priority: .userInitiated) {
            let p = PersistenceController.shared                        // SQLite open
            let d = StorageLocationService.shared.resolvedBaseDirectory // bookmark resolve
            return (p, d)
        }.value
        return AppContainer(persistence: persistence, baseDirectory: baseDir)
    }

    /// Convenience init for Xcode previews — synchronous, main-thread only.
    convenience init() {
        self.init(
            persistence: PersistenceController.shared,
            baseDirectory: StorageLocationService.shared.resolvedBaseDirectory
        )
    }

    // MARK: - App lifecycle hooks

    func onAppBecomeActive() {
        Task {
            await auth.restorePreviousSignIn()
            await receiveSharedFiles()
            _ = await periodicBackup.backupIfDue()
            if auth.isAuthenticated {
                tokenRefresher.start(authService: auth)
                if UserDefaults.standard.bool(forKey: "autoSyncEnabled") {
                    await sync.syncPendingItems()
                }
            }
        }
    }

    func onAppBackground() {
        Task { await publishShareCatalog() }
        BackgroundSyncTask.schedule()
        periodicBackup.scheduleNextBackgroundRun()
    }

    func onSignificantTimeChange() {
        periodicBackup.handleSignificantTimeChange()
    }
}
