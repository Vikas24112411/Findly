import Foundation
import BackgroundTasks

/// Registers and schedules the background sync `BGProcessingTask`.
///
/// `Info.plist` must include:
/// ```xml
/// <key>BGTaskSchedulerPermittedIdentifiers</key>
/// <array>
///     <string>com.findly.app.sync</string>
/// </array>
/// ```
enum BackgroundSyncTask {

    static let identifier = "com.findly.app.sync"

    // MARK: - Registration (call once at app launch)

    static func register(syncService: SyncService) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: processingTask, syncService: syncService)
        }
    }

    // MARK: - Scheduling

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // iOS will fire this when it thinks the device is idle,
        // but no earlier than 15 minutes from now.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch BGTaskScheduler.Error.notPermitted {
            // BGTaskSchedulerPermittedIdentifiers not set in Info.plist.
            // This is expected in Simulator — no action needed.
            return
        } catch {
            // Scheduling failed — not critical, sync happens on next foreground.
            return
        }
    }

    // MARK: - Execution

    private static func handle(task: BGProcessingTask, syncService: SyncService) {
        // Schedule the next background sync before this one starts.
        schedule()

        let syncTask = Task {
            await syncService.syncPendingItems()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
