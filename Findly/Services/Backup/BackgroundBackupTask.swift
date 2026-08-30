import BackgroundTasks
import Foundation

@MainActor
protocol BackupTaskScheduling: AnyObject {
    func schedule(earliestBeginDate: Date)
    func cancel()
}

@MainActor
final class SystemBackupTaskScheduler: BackupTaskScheduling {
    func schedule(earliestBeginDate: Date) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundBackupTask.identifier)

        let request = BGProcessingTaskRequest(identifier: BackgroundBackupTask.identifier)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Foreground activation performs the same due check, so an unavailable
            // background scheduler does not prevent backups entirely.
        }
    }

    func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundBackupTask.identifier)
    }
}

enum BackgroundBackupTask {
    static let identifier = "com.findlyvikas.app.periodic-backup"

    @MainActor
    static func register(service: PeriodicBackupService) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: processingTask, service: service)
        }
    }

    private static func handle(
        task: BGProcessingTask,
        service: PeriodicBackupService
    ) {
        let state = BackgroundCompletionState()
        let operation = Task { @MainActor in
            let success = await service.backupIfDue()
            if state.claimCompletion() {
                task.setTaskCompleted(success: success)
            }
        }

        task.expirationHandler = {
            operation.cancel()
            if state.claimCompletion() {
                task.setTaskCompleted(success: false)
            }
        }
    }
}

private final class BackgroundCompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func claimCompletion() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}
