import Foundation
import Observation
import SwiftData

enum PeriodicBackupError: LocalizedError {
    case destinationMissing
    case destinationUnavailable

    var errorDescription: String? {
        switch self {
        case .destinationMissing:
            return "Choose a backup folder before enabling periodic backup."
        case .destinationUnavailable:
            return "The backup folder is unavailable. Choose the folder again and retry."
        }
    }
}

@Observable
@MainActor
final class PeriodicBackupService {
    nonisolated static let backupFileName = "Findly_AutoBackup.zip"
    static let retryInterval: TimeInterval = 60 * 60

    private enum Keys {
        static let enabled = "periodicBackup.enabled"
        static let frequency = "periodicBackup.frequency"
        static let hour = "periodicBackup.hour"
        static let minute = "periodicBackup.minute"
        static let weekday = "periodicBackup.weekday"
        static let folderBookmark = "periodicBackup.folderBookmark"
        static let folderName = "periodicBackup.folderName"
        static let scheduleEstablishedAt = "periodicBackup.scheduleEstablishedAt"
        static let lastHandledOccurrence = "periodicBackup.lastHandledOccurrence"
        static let pendingImmediateBackup = "periodicBackup.pendingImmediateBackup"
        static let lastAttempt = "periodicBackup.lastAttempt"
        static let retryNotBefore = "periodicBackup.retryNotBefore"
        static let lastSuccess = "periodicBackup.lastSuccess"
        static let latestError = "periodicBackup.latestError"
    }

    private let exportService: ExportService
    private let localStorage: LocalFileService
    private let modelContainer: ModelContainer
    private let scheduler: BackupTaskScheduling
    private let defaults: UserDefaults
    private let calendarOverride: Calendar?
    private var activeDestinationURL: URL?
    private var isAccessingDestination = false

    private(set) var isEnabled: Bool
    private(set) var schedule: BackupSchedule
    private(set) var folderDisplayName: String?
    private(set) var scheduleEstablishedAt: Date
    private(set) var lastHandledOccurrence: Date?
    private(set) var pendingImmediateBackup: Bool
    private(set) var lastAttempt: Date?
    private var retryNotBefore: Date?
    private(set) var lastSuccess: Date?
    private(set) var latestError: String?

    private(set) var isRunning = false
    private(set) var progress: Double = 0

    var hasDestination: Bool {
        defaults.data(forKey: Keys.folderBookmark) != nil
    }

    var nextScheduledDate: Date? {
        schedule.nextOccurrence(after: Date(), calendar: currentCalendar)
    }

    init(
        exportService: ExportService,
        localStorage: LocalFileService,
        modelContainer: ModelContainer,
        scheduler: BackupTaskScheduling? = nil,
        defaults: UserDefaults = .standard,
        calendar: Calendar? = nil
    ) {
        self.exportService = exportService
        self.localStorage = localStorage
        self.modelContainer = modelContainer
        self.scheduler = scheduler ?? SystemBackupTaskScheduler()
        self.defaults = defaults
        calendarOverride = calendar

        isEnabled = defaults.bool(forKey: Keys.enabled)
        schedule = BackupSchedule(
            frequency: BackupFrequency(
                rawValue: defaults.string(forKey: Keys.frequency) ?? ""
            ) ?? .daily,
            hour: defaults.object(forKey: Keys.hour) as? Int ?? 21,
            minute: defaults.object(forKey: Keys.minute) as? Int ?? 0,
            weekday: defaults.object(forKey: Keys.weekday) as? Int ?? 1
        )
        folderDisplayName = defaults.string(forKey: Keys.folderName)
        scheduleEstablishedAt = defaults.object(forKey: Keys.scheduleEstablishedAt) as? Date ?? Date()
        lastHandledOccurrence = defaults.object(forKey: Keys.lastHandledOccurrence) as? Date
        pendingImmediateBackup = defaults.bool(forKey: Keys.pendingImmediateBackup)
        lastAttempt = defaults.object(forKey: Keys.lastAttempt) as? Date
        retryNotBefore = defaults.object(forKey: Keys.retryNotBefore) as? Date
        lastSuccess = defaults.object(forKey: Keys.lastSuccess) as? Date
        latestError = defaults.string(forKey: Keys.latestError)

        // A restored enabled setting without a usable bookmark needs user attention.
        if isEnabled && defaults.data(forKey: Keys.folderBookmark) == nil {
            isEnabled = false
            defaults.set(false, forKey: Keys.enabled)
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled != isEnabled else { return }

        if enabled {
            guard hasDestination else { throw PeriodicBackupError.destinationMissing }
            _ = try resolveDestinationURL()
            isEnabled = true
            pendingImmediateBackup = true
            scheduleEstablishedAt = Date()
            lastHandledOccurrence = nil
            lastAttempt = nil
            retryNotBefore = nil
            persistState()
            scheduleNextBackgroundRun()
            Task { @MainActor [weak self] in
                _ = await self?.backupIfDue()
            }
        } else {
            isEnabled = false
            pendingImmediateBackup = false
            defaults.set(false, forKey: Keys.enabled)
            defaults.set(false, forKey: Keys.pendingImmediateBackup)
            scheduler.cancel()
        }
    }

    /// Stores a durable security-scoped bookmark. If backups are already enabled,
    /// the new destination receives an immediate backup while the old ZIP is retained.
    func setDestination(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        if isAccessingDestination {
            activeDestinationURL?.stopAccessingSecurityScopedResource()
        }
        activeDestinationURL = nil
        isAccessingDestination = false
        defaults.set(bookmark, forKey: Keys.folderBookmark)
        folderDisplayName = url.lastPathComponent
        defaults.set(folderDisplayName, forKey: Keys.folderName)

        // Resolve the saved bookmark now so stale/invalid destinations fail while
        // the picker result is still in front of the user.
        _ = try resolveDestinationURL()

        if isEnabled {
            pendingImmediateBackup = true
            lastAttempt = nil
            retryNotBefore = nil
            persistState()
            Task { @MainActor [weak self] in
                _ = await self?.backupIfDue()
            }
        }
        scheduleNextBackgroundRun()
    }

    func updateFrequency(_ frequency: BackupFrequency) {
        guard schedule.frequency != frequency else { return }
        schedule.frequency = frequency
        establishUpdatedSchedule()
    }

    func updateTime(hour: Int, minute: Int) {
        let updated = BackupSchedule(
            frequency: schedule.frequency,
            hour: hour,
            minute: minute,
            weekday: schedule.weekday
        )
        guard updated != schedule else { return }
        schedule = updated
        establishUpdatedSchedule()
    }

    func updateWeekday(_ weekday: Int) {
        let updated = BackupSchedule(
            frequency: schedule.frequency,
            hour: schedule.hour,
            minute: schedule.minute,
            weekday: weekday
        )
        guard updated != schedule else { return }
        schedule = updated
        establishUpdatedSchedule()
    }

    func handleSignificantTimeChange() {
        scheduleNextBackgroundRun()
    }

    /// Performs one catch-up backup when an occurrence is due. Multiple missed
    /// occurrences collapse to the most recent occurrence.
    @discardableResult
    func backupIfDue(now: Date = Date()) async -> Bool {
        guard isEnabled else {
            scheduler.cancel()
            return true
        }
        guard !isRunning else { return true }

        let dueOccurrence = schedule.dueOccurrence(
            at: now,
            establishedAt: scheduleEstablishedAt,
            lastHandledOccurrence: lastHandledOccurrence,
            calendar: currentCalendar
        )
        guard pendingImmediateBackup || dueOccurrence != nil else {
            scheduleNextBackgroundRun(now: now)
            return true
        }

        if let retryNotBefore, now < retryNotBefore {
            scheduleNextBackgroundRun(now: now)
            return true
        }

        return await performBackup(
            scheduledOccurrence: dueOccurrence,
            clearsPendingImmediateBackup: pendingImmediateBackup,
            isAutomaticAttempt: true
        )
    }

    /// A user-requested backup does not mark a scheduled occurrence as handled and
    /// therefore never postpones the fixed calendar schedule.
    @discardableResult
    func backupNow() async -> Bool {
        guard hasDestination, !isRunning else { return false }
        return await performBackup(
            scheduledOccurrence: nil,
            clearsPendingImmediateBackup: pendingImmediateBackup,
            isAutomaticAttempt: false
        )
    }

    func scheduleNextBackgroundRun(now: Date = Date()) {
        guard isEnabled else {
            scheduler.cancel()
            return
        }

        let dueOccurrence = schedule.dueOccurrence(
            at: now,
            establishedAt: scheduleEstablishedAt,
            lastHandledOccurrence: lastHandledOccurrence,
            calendar: currentCalendar
        )

        if pendingImmediateBackup || dueOccurrence != nil {
            let retryDate = retryNotBefore ?? now
            scheduler.schedule(earliestBeginDate: max(now, retryDate))
        } else if let next = schedule.nextOccurrence(after: now, calendar: currentCalendar) {
            scheduler.schedule(earliestBeginDate: next)
        }
    }

    private var currentCalendar: Calendar {
        calendarOverride ?? .autoupdatingCurrent
    }

    private func establishUpdatedSchedule() {
        scheduleEstablishedAt = Date()
        lastHandledOccurrence = nil
        persistState()
        scheduleNextBackgroundRun()
    }

    private func performBackup(
        scheduledOccurrence: Date?,
        clearsPendingImmediateBackup: Bool,
        isAutomaticAttempt: Bool
    ) async -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        progress = 0
        lastAttempt = Date()
        defaults.set(lastAttempt, forKey: Keys.lastAttempt)
        defer { isRunning = false }

        var temporaryArchive: URL?
        defer {
            if let temporaryArchive {
                try? FileManager.default.removeItem(at: temporaryArchive)
            }
        }

        do {
            try Task.checkCancellation()
            let destination = try resolveDestinationURL()
            let context = modelContainer.mainContext
            let items = try context.fetch(FetchDescriptor<Item>())
            let tags = try context.fetch(FetchDescriptor<Tag>())
            let history = try context.fetch(FetchDescriptor<SearchHistoryEntry>())

            let archive = try await exportService.exportVault(
                items: items,
                tags: tags,
                searchHistory: history,
                localStorage: localStorage,
                onProgress: { @MainActor [weak self] value in
                    // Leave room for copying the archive into the backup folder,
                    // so 100% only appears once the backup is actually in place.
                    self?.progress = value * 0.95
                }
            )
            temporaryArchive = archive
            try Task.checkCancellation()
            try await Self.installArchive(archive, in: destination)

            let completedAt = Date()
            lastSuccess = completedAt
            latestError = nil
            retryNotBefore = nil
            if clearsPendingImmediateBackup {
                pendingImmediateBackup = false
            }
            if let scheduledOccurrence {
                lastHandledOccurrence = scheduledOccurrence
            }
            progress = 1
            persistState()
            scheduleNextBackgroundRun(now: completedAt)
            return true
        } catch {
            latestError = error is CancellationError
                ? "The backup was interrupted and will be retried."
                : error.localizedDescription
            if isAutomaticAttempt {
                retryNotBefore = Date().addingTimeInterval(Self.retryInterval)
                defaults.set(retryNotBefore, forKey: Keys.retryNotBefore)
            }
            defaults.set(latestError, forKey: Keys.latestError)
            scheduleNextBackgroundRun()
            return false
        }
    }

    nonisolated static func installArchive(_ archive: URL, in folder: URL) async throws {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let fileManager = FileManager.default
            let finalURL = folder.appending(component: backupFileName)
            let partialURL = folder.appending(component: ".Findly_AutoBackup.partial.zip")

            try? fileManager.removeItem(at: partialURL)
            var installed = false
            defer {
                if !installed { try? fileManager.removeItem(at: partialURL) }
            }

            try fileManager.copyItem(at: archive, to: partialURL)
            try Task.checkCancellation()

            if fileManager.fileExists(atPath: finalURL.path) {
                _ = try fileManager.replaceItemAt(finalURL, withItemAt: partialURL)
            } else {
                try fileManager.moveItem(at: partialURL, to: finalURL)
            }
            installed = true
        }.value
    }

    private func resolveDestinationURL() throws -> URL {
        if let activeDestinationURL {
            return activeDestinationURL
        }
        guard let bookmark = defaults.data(forKey: Keys.folderBookmark) else {
            throw PeriodicBackupError.destinationMissing
        }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            throw PeriodicBackupError.destinationUnavailable
        }

        isAccessingDestination = url.startAccessingSecurityScopedResource()
        activeDestinationURL = url

        if stale, let refreshed = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(refreshed, forKey: Keys.folderBookmark)
        }
        return url
    }

    private func persistState() {
        defaults.set(isEnabled, forKey: Keys.enabled)
        defaults.set(schedule.frequency.rawValue, forKey: Keys.frequency)
        defaults.set(schedule.hour, forKey: Keys.hour)
        defaults.set(schedule.minute, forKey: Keys.minute)
        defaults.set(schedule.weekday, forKey: Keys.weekday)
        defaults.set(scheduleEstablishedAt, forKey: Keys.scheduleEstablishedAt)
        defaults.set(lastHandledOccurrence, forKey: Keys.lastHandledOccurrence)
        defaults.set(pendingImmediateBackup, forKey: Keys.pendingImmediateBackup)
        defaults.set(lastAttempt, forKey: Keys.lastAttempt)
        defaults.set(retryNotBefore, forKey: Keys.retryNotBefore)
        defaults.set(lastSuccess, forKey: Keys.lastSuccess)

        if let latestError {
            defaults.set(latestError, forKey: Keys.latestError)
        } else {
            defaults.removeObject(forKey: Keys.latestError)
        }
    }
}
