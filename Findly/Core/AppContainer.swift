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

    // MARK: - Init

    init() {
        persistence    = PersistenceController.shared
        auth           = AuthService()
        drive          = GoogleDriveService(auth: auth)
        tokenRefresher = TokenRefresher.shared

        // LocalFileService base directory is resolved from the user's saved preference.
        // Defaults to ApplicationSupport/Findly/files/ on first launch.
        let baseDir = StorageLocationService.shared.resolvedBaseDirectory
        guard let localFS = try? LocalFileService(baseDirectory: baseDir) else {
            fatalError("Could not initialize local file storage.")
        }
        localStorage = localFS

        sync = SyncService(
            drive: drive,
            auth: auth,
            localStorage: localStorage,
            context: persistence.container.mainContext
        )

        // Register BGProcessingTask handler
        BackgroundSyncTask.register(syncService: sync)
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
