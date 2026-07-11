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

    // MARK: - Init

    init() {
        persistence    = PersistenceController.shared
        auth           = AuthService()
        drive          = GoogleDriveService(auth: auth)
        tokenRefresher = TokenRefresher.shared

        // LocalFileService can throw if AppSupport directory creation fails.
        // This should never happen in practice on a real device.
        guard let localFS = try? LocalFileService() else {
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
                await sync.syncPendingItems()
            }
        }
    }

    func onAppBackground() {
        BackgroundSyncTask.schedule()
    }
}
