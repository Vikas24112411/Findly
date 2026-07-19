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

        BackgroundSyncTask.register(syncService: sync)
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
            if auth.isAuthenticated {
                tokenRefresher.start(authService: auth)
                if UserDefaults.standard.bool(forKey: "autoSyncEnabled") {
                    await sync.syncPendingItems()
                }
            }
        }
    }

    func onAppBackground() {
        BackgroundSyncTask.schedule()
    }
}
