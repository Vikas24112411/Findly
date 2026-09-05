import Testing
import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit
@testable import Findly

// MARK: - Files sort control tests

@Suite("Files Sort Control")
@MainActor
struct FilesSortControlTests {

    @Test("Every sort option preserves the same pill footprint")
    func stableFootprintAcrossSelections() throws {
        let options: [SearchService.SortOrder] = [
            .modifiedAt, .createdAt, .title, .viewCount, .fileSize
        ]
        let typeSizes: [DynamicTypeSize] = [.large, .accessibility3]

        for typeSize in typeSizes {
            let reference = try renderedSize(for: .modifiedAt, typeSize: typeSize)

            for option in options {
                let size = try renderedSize(for: option, typeSize: typeSize)
                #expect(abs(size.width - reference.width) < 0.5)
                #expect(size.height >= 44)
            }
        }
    }

    @Test("Repeated selection changes keep the live menu footprint stable")
    func repeatedLiveSelectionChanges() async throws {
        let options: [SearchService.SortOrder] = [
            .modifiedAt, .createdAt, .title, .viewCount, .fileSize
        ]
        let reversedOptions = Array(options.reversed())
        let sequence = options + reversedOptions + options + reversedOptions

        for typeSize in [DynamicTypeSize.large, .accessibility3] {
            let state = FilesSortControlTestState()
            let controller = UIHostingController(
                rootView: FilesSortControlTestHost(state: state, typeSize: typeSize)
            )
            controller.loadViewIfNeeded()

            let reference = controller.sizeThatFits(
                in: CGSize(width: 600, height: 240)
            )

            for option in sequence {
                state.selection = option
                await Task.yield()
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()

                let size = controller.sizeThatFits(
                    in: CGSize(width: 600, height: 240)
                )
                #expect(abs(size.width - reference.width) < 0.5)
                #expect(size.height >= 44)
            }
        }
    }

    private func renderedSize(
        for sortOrder: SearchService.SortOrder,
        typeSize: DynamicTypeSize
    ) throws -> CGSize {
        let renderer = ImageRenderer(
            content: FilesSortPillLabel(sortOrder: sortOrder)
                .environment(\.dynamicTypeSize, typeSize)
        )
        renderer.scale = 1
        return try #require(renderer.uiImage).size
    }
}

@Observable
@MainActor
private final class FilesSortControlTestState {
    var selection: SearchService.SortOrder = .modifiedAt
}

private struct FilesSortControlTestHost: View {
    @Bindable var state: FilesSortControlTestState
    let typeSize: DynamicTypeSize

    var body: some View {
        FilesSortMenu(selection: $state.selection)
            .environment(\.dynamicTypeSize, typeSize)
    }
}

@MainActor
private final class FakeBackupTaskScheduler: BackupTaskScheduling {
    private(set) var scheduledDates: [Date] = []
    private(set) var cancellationCount = 0

    func schedule(earliestBeginDate: Date) {
        scheduledDates.append(earliestBeginDate)
    }

    func cancel() {
        cancellationCount += 1
    }
}

// MARK: - File viewer tests

@Suite("File Viewer")
@MainActor
struct FileViewerTests {

    @Test("Resolution prefers an available local file")
    func localResolution() {
        #expect(FileResolutionStrategy.choose(hasLocalFile: true, hasRemoteFile: true) == .useLocalFile)
        #expect(FileResolutionStrategy.choose(hasLocalFile: true, hasRemoteFile: false) == .useLocalFile)
    }

    @Test("Resolution recovers a missing local file when a Drive copy exists")
    func driveRecoveryResolution() {
        #expect(FileResolutionStrategy.choose(hasLocalFile: false, hasRemoteFile: true) == .recoverFromDrive)
    }

    @Test("Resolution reports unavailable when neither copy exists")
    func unavailableResolution() {
        #expect(FileResolutionStrategy.choose(hasLocalFile: false, hasRemoteFile: false) == .unavailable)
    }

    @Test("A viewer session records a successful open exactly once")
    func openCountIsIdempotent() {
        let item = Item(title: "Document", fileType: .pdf)
        var session = FileOpenSession()

        let firstOpen = session.recordOpen(for: item)
        let secondOpen = session.recordOpen(for: item)

        #expect(firstOpen)
        #expect(!secondOpen)
        #expect(item.viewCount == 1)
        #expect(item.lastOpenedAt != nil)
    }
}

// MARK: - Periodic backup schedule tests

@Suite("Periodic Backup Schedule")
struct PeriodicBackupScheduleTests {

    @Test("Daily schedule becomes due at its fixed local time")
    func dailyFixedTime() throws {
        let calendar = utcCalendar
        let schedule = BackupSchedule(frequency: .daily, hour: 9, minute: 30)
        let established = try date(2026, 8, 29, 10, 0, calendar: calendar)
        let expectedOccurrence = try date(2026, 8, 30, 9, 30, calendar: calendar)

        #expect(schedule.dueOccurrence(
            at: try date(2026, 8, 30, 9, 29, calendar: calendar),
            establishedAt: established,
            lastHandledOccurrence: nil,
            calendar: calendar
        ) == nil)

        #expect(schedule.dueOccurrence(
            at: try date(2026, 8, 30, 9, 30, calendar: calendar),
            establishedAt: established,
            lastHandledOccurrence: nil,
            calendar: calendar
        ) == expectedOccurrence)
    }

    @Test("A handled daily occurrence does not drift from the fixed time")
    func handledDailyOccurrence() throws {
        let calendar = utcCalendar
        let schedule = BackupSchedule(frequency: .daily, hour: 21, minute: 0)
        let established = try date(2026, 8, 29, 12, 0, calendar: calendar)
        let handled = try date(2026, 8, 30, 21, 0, calendar: calendar)
        let nextDay = try date(2026, 8, 31, 21, 0, calendar: calendar)

        #expect(schedule.dueOccurrence(
            at: try date(2026, 8, 31, 20, 59, calendar: calendar),
            establishedAt: established,
            lastHandledOccurrence: handled,
            calendar: calendar
        ) == nil)
        #expect(schedule.nextOccurrence(after: handled, calendar: calendar) == nextDay)
    }

    @Test("Weekly schedules use the selected weekday and wrap into the next week")
    func weeklyWeekdayAndWrap() throws {
        let calendar = utcCalendar
        // Sunday at 18:15. August 30, 2026 is a Sunday.
        let schedule = BackupSchedule(frequency: .weekly, hour: 18, minute: 15, weekday: 1)
        let before = try date(2026, 8, 30, 18, 14, calendar: calendar)
        let occurrence = try date(2026, 8, 30, 18, 15, calendar: calendar)
        let followingWeek = try date(2026, 9, 6, 18, 15, calendar: calendar)

        #expect(schedule.nextOccurrence(after: before, calendar: calendar) == occurrence)
        #expect(schedule.nextOccurrence(after: occurrence, calendar: calendar) == followingWeek)
    }

    @Test("Weekly schedules support every calendar weekday")
    func everyWeeklyWeekday() throws {
        let calendar = utcCalendar
        let sundayMorning = try date(2026, 8, 30, 0, 0, calendar: calendar)

        for weekday in 1...7 {
            let schedule = BackupSchedule(
                frequency: .weekly,
                hour: 12,
                minute: 45,
                weekday: weekday
            )
            let next = try #require(schedule.nextOccurrence(after: sundayMorning, calendar: calendar))
            let components = calendar.dateComponents([.weekday, .hour, .minute], from: next)
            #expect(components.weekday == weekday)
            #expect(components.hour == 12)
            #expect(components.minute == 45)
        }
    }

    @Test("Multiple missed occurrences collapse to the most recent one")
    func missedOccurrencesCollapse() throws {
        let calendar = utcCalendar
        let schedule = BackupSchedule(frequency: .daily, hour: 7, minute: 0)
        let due = schedule.dueOccurrence(
            at: try date(2026, 8, 30, 20, 0, calendar: calendar),
            establishedAt: try date(2026, 8, 25, 12, 0, calendar: calendar),
            lastHandledOccurrence: try date(2026, 8, 26, 7, 0, calendar: calendar),
            calendar: calendar
        )
        let expectedOccurrence = try date(2026, 8, 30, 7, 0, calendar: calendar)

        #expect(due == expectedOccurrence)
    }

    @Test("Changing a schedule ignores occurrences before the edit")
    func scheduleEditCreatesNewBaseline() throws {
        let calendar = utcCalendar
        let schedule = BackupSchedule(frequency: .daily, hour: 8, minute: 0)
        let editedAt = try date(2026, 8, 30, 10, 0, calendar: calendar)
        let nextDay = try date(2026, 8, 31, 8, 0, calendar: calendar)

        #expect(schedule.dueOccurrence(
            at: editedAt,
            establishedAt: editedAt,
            lastHandledOccurrence: nil,
            calendar: calendar
        ) == nil)
        #expect(schedule.nextOccurrence(after: editedAt, calendar: calendar) == nextDay)
    }

    @Test("Nonexistent daylight-saving time advances to the next valid local time")
    func daylightSavingGap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let schedule = BackupSchedule(frequency: .daily, hour: 2, minute: 30)
        let beforeGap = try date(2026, 3, 7, 3, 0, calendar: calendar)
        let next = try #require(schedule.nextOccurrence(after: beforeGap, calendar: calendar))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)

        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 8)
        #expect(components.hour == 3)
        #expect(components.minute == 0)
    }

    @Test("Repeated daylight-saving time consistently chooses the first occurrence")
    func daylightSavingOverlap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let schedule = BackupSchedule(frequency: .daily, hour: 1, minute: 30)
        let beforeOverlap = try date(2026, 10, 31, 3, 0, calendar: calendar)
        let next = try #require(schedule.nextOccurrence(after: beforeOverlap, calendar: calendar))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)

        #expect(components.year == 2026)
        #expect(components.month == 11)
        #expect(components.day == 1)
        #expect(components.hour == 1)
        #expect(components.minute == 30)
        #expect(calendar.timeZone.secondsFromGMT(for: next) == -7 * 60 * 60)
    }

    @Test("Schedule follows local clock time after a timezone change")
    func followsLocalTimezone() throws {
        let schedule = BackupSchedule(frequency: .daily, hour: 9, minute: 0)
        var india = Calendar(identifier: .gregorian)
        india.timeZone = try #require(TimeZone(identifier: "Asia/Kolkata"))
        var london = Calendar(identifier: .gregorian)
        london.timeZone = try #require(TimeZone(identifier: "Europe/London"))

        let reference = try date(2026, 8, 30, 0, 0, calendar: utcCalendar)
        let indiaNext = try #require(schedule.nextOccurrence(after: reference, calendar: india))
        let londonNext = try #require(schedule.nextOccurrence(after: reference, calendar: london))

        #expect(india.dateComponents([.hour, .minute], from: indiaNext).hour == 9)
        #expect(london.dateComponents([.hour, .minute], from: londonNext).hour == 9)
        #expect(indiaNext != londonNext)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }
}

@Suite("Periodic Backup Service")
@MainActor
struct PeriodicBackupServiceTests {

    @Test("Enabling commits immediately and creates the first backup asynchronously")
    func enablingTurnsToggleOnImmediately() async throws {
        let suiteName = "PeriodicBackupEnableTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let destination = FileManager.default.temporaryDirectory
            .appending(component: "FindlyBackupEnableDestination-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let scheduler = FakeBackupTaskScheduler()
        let service = try makeService(defaults: defaults, scheduler: scheduler)
        try service.setDestination(destination)
        try service.setEnabled(true)

        // The setting must commit before the potentially long ZIP export completes.
        #expect(service.isEnabled)
        #expect(defaults.bool(forKey: "periodicBackup.enabled"))

        let backupURL = destination.appending(component: PeriodicBackupService.backupFileName)
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: backupURL.path) {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
    }

    @Test("Enabled service schedules the next fixed calendar occurrence")
    func schedulesNextOccurrence() throws {
        let suiteName = "PeriodicBackupServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try makeDate(2026, 8, 30, 8, 0, calendar: calendar)
        let expected = try makeDate(2026, 8, 30, 9, 0, calendar: calendar)
        defaults.set(true, forKey: "periodicBackup.enabled")
        defaults.set(Data([0x01]), forKey: "periodicBackup.folderBookmark")
        defaults.set("daily", forKey: "periodicBackup.frequency")
        defaults.set(9, forKey: "periodicBackup.hour")
        defaults.set(0, forKey: "periodicBackup.minute")
        defaults.set(try makeDate(2026, 8, 29, 12, 0, calendar: calendar),
                     forKey: "periodicBackup.scheduleEstablishedAt")

        let scheduler = FakeBackupTaskScheduler()
        let service = try makeService(defaults: defaults, scheduler: scheduler, calendar: calendar)
        service.scheduleNextBackgroundRun(now: now)

        #expect(scheduler.scheduledDates.last == expected)
    }

    @Test("Disabling periodic backup cancels its pending background request")
    func disablingCancelsRequest() async throws {
        let suiteName = "PeriodicBackupDisableTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "periodicBackup.enabled")
        defaults.set(Data([0x01]), forKey: "periodicBackup.folderBookmark")

        let scheduler = FakeBackupTaskScheduler()
        let service = try makeService(defaults: defaults, scheduler: scheduler)
        try service.setEnabled(false)

        #expect(service.isEnabled == false)
        #expect(scheduler.cancellationCount == 1)
    }

    @Test("Archive installation replaces only after a complete staged copy")
    func atomicArchiveInstallation() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(component: "FindlyBackupInstallTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let finalURL = folder.appending(component: PeriodicBackupService.backupFileName)
        let sourceURL = folder.appending(component: "new.zip")
        try Data("old".utf8).write(to: finalURL)
        try Data("new".utf8).write(to: sourceURL)

        try await PeriodicBackupService.installArchive(sourceURL, in: folder)

        #expect(try Data(contentsOf: finalURL) == Data("new".utf8))
        #expect(!FileManager.default.fileExists(
            atPath: folder.appending(component: ".Findly_AutoBackup.partial.zip").path
        ))
    }

    @Test("Failed staging leaves the previous backup untouched")
    func failedInstallPreservesPreviousBackup() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(component: "FindlyBackupFailureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let finalURL = folder.appending(component: PeriodicBackupService.backupFileName)
        let missingSource = folder.appending(component: "missing.zip")
        try Data("old".utf8).write(to: finalURL)

        await #expect(throws: (any Error).self) {
            try await PeriodicBackupService.installArchive(missingSource, in: folder)
        }
        #expect(try Data(contentsOf: finalURL) == Data("old".utf8))
    }

    @Test("Automatic backup archive round-trips through the existing importer")
    func automaticBackupRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(component: "FindlyBackupRoundTrip-\(UUID().uuidString)")
        let sourceFolder = root.appending(component: "source")
        let restoredFolder = root.appending(component: "restored")
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceStorage = try LocalFileService(baseDirectory: sourceFolder)
        let sourcePersistence = PersistenceController(inMemory: true)
        let sourceContext = sourcePersistence.container.mainContext

        let parent = Tag(name: "Work")
        let child = Tag(name: "Reports")
        child.parents = [parent]
        parent.children = [child]
        let item = Item(
            title: "Quarterly Report",
            fileType: .pdf,
            fileSize: 4,
            originalFileName: "report.pdf"
        )
        item.localFilePath = try await sourceStorage.write(
            data: Data("file".utf8),
            itemID: item.id,
            fileExtension: "pdf"
        )
        item.thumbnailData = Data("thumb".utf8)
        item.tags = [child]
        item.isFavorite = true
        item.isPinned = true
        let history = SearchHistoryEntry(query: "quarterly")
        history.recordUse()

        sourceContext.insert(parent)
        sourceContext.insert(child)
        sourceContext.insert(item)
        sourceContext.insert(history)
        try sourceContext.save()

        let archive = try await ExportService().exportVault(
            items: [item],
            tags: [parent, child],
            searchHistory: [history],
            localStorage: sourceStorage
        )
        defer { try? FileManager.default.removeItem(at: archive) }

        let restoredStorage = try LocalFileService(baseDirectory: restoredFolder)
        let restoredPersistence = PersistenceController(inMemory: true)
        try await ImportService().importVault(
            from: archive,
            localStorage: restoredStorage,
            context: restoredPersistence.container.mainContext
        )

        let verificationContext = ModelContext(restoredPersistence.container)
        let restoredItems = try verificationContext.fetch(FetchDescriptor<Item>())
        let restoredTags = try verificationContext.fetch(FetchDescriptor<Findly.Tag>())
        let restoredHistory = try verificationContext.fetch(FetchDescriptor<SearchHistoryEntry>())
        let restoredItem = try #require(restoredItems.first)

        #expect(restoredItems.count == 1)
        #expect(restoredItem.title == "Quarterly Report")
        #expect(restoredItem.isFavorite)
        #expect(restoredItem.isPinned)
        #expect(restoredItem.thumbnailData == Data("thumb".utf8))
        #expect(restoredItem.tags.map(\.name) == ["Reports"])
        #expect(restoredTags.count == 2)
        #expect(restoredTags.first(where: { $0.name == "Reports" })?.parents.map(\.name) == ["Work"])
        #expect(restoredHistory.first?.query == "quarterly")
        #expect(restoredHistory.first?.useCount == 2)

        let restoredPath = try #require(restoredItem.localFilePath)
        #expect(try await restoredStorage.read(relativePath: restoredPath) == Data("file".utf8))
    }

    private func makeService(
        defaults: UserDefaults,
        scheduler: FakeBackupTaskScheduler,
        calendar: Calendar? = nil
    ) throws -> PeriodicBackupService {
        let storageURL = FileManager.default.temporaryDirectory
            .appending(component: "FindlyBackupStorage-\(UUID().uuidString)")
        let localStorage = try LocalFileService(baseDirectory: storageURL)
        let persistence = PersistenceController(inMemory: true)
        return PeriodicBackupService(
            exportService: ExportService(),
            localStorage: localStorage,
            modelContainer: persistence.container,
            scheduler: scheduler,
            defaults: defaults,
            calendar: calendar
        )
    }

    private func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }
}

// MARK: - Delete all data tests

@Suite("Delete All Data")
@MainActor
struct DeleteAllDataTests {

    @Test("Wipes records and files through an isolated context")
    func wipesRecordsAndFiles() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(component: "FindlyDeleteAllTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        let storage = try LocalFileService(baseDirectory: folder)
        let persistence = PersistenceController(inMemory: true)
        let mainContext = persistence.container.mainContext

        let tag = Tag(name: "Work")
        let item = Item(title: "Report", fileType: .pdf)
        item.tags = [tag]
        item.localFilePath = try await storage.write(
            data: Data("contents".utf8),
            itemID: item.id,
            fileExtension: "pdf"
        )
        let history = SearchHistoryEntry(query: "report")

        mainContext.insert(tag)
        mainContext.insert(item)
        mainContext.insert(history)
        try mainContext.save()

        let viewModel = SettingsViewModel()
        await viewModel.deleteAllData(localStorage: storage, context: mainContext)

        let verificationContext = ModelContext(persistence.container)
        #expect(try verificationContext.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(try verificationContext.fetchCount(FetchDescriptor<Findly.Tag>()) == 0)
        #expect(try verificationContext.fetchCount(FetchDescriptor<SearchHistoryEntry>()) == 0)
        #expect(await storage.sizeOfLocalStorage() == 0)
        #expect(viewModel.deleteError == nil)
        #expect(!viewModel.isDeletingAll)
    }
}

// MARK: - TagGraphTraverser Tests

@Suite("TagGraphTraverser")
struct TagGraphTraverserTests {

    // MARK: - Descendants

    @Test("allDescendants returns root only for leaf node")
    func leafNodeDescendants() {
        let leaf = Tag(name: "Lion")
        let result = TagGraphTraverser.allDescendants(of: leaf)
        #expect(result.count == 1)
        #expect(result.contains(leaf))
    }

    @Test("allDescendants traverses multi-level hierarchy")
    func multiLevelDescendants() {
        let animals   = Tag(name: "Animals")
        let mammals   = Tag(name: "Mammals")
        let lion      = Tag(name: "Lion")

        // Wire up: Animals → Mammals → Lion
        mammals.parents.append(animals)
        animals.children.append(mammals)
        lion.parents.append(mammals)
        mammals.children.append(lion)

        let result = TagGraphTraverser.allDescendants(of: animals)
        #expect(result.count == 3)
        #expect(result.contains(animals))
        #expect(result.contains(mammals))
        #expect(result.contains(lion))
    }

    @Test("allDescendants handles DAG with shared children")
    func dagSharedDescendant() {
        let wildlife  = Tag(name: "Wildlife")
        let africa    = Tag(name: "Africa")
        let lion      = Tag(name: "Lion") // has two parents

        wildlife.children.append(lion)
        lion.parents.append(wildlife)
        africa.children.append(lion)
        lion.parents.append(africa)

        let wildlifeDesc = TagGraphTraverser.allDescendants(of: wildlife)
        #expect(wildlifeDesc.count == 2) // wildlife + lion (no duplicates)

        let africaDesc = TagGraphTraverser.allDescendants(of: africa)
        #expect(africaDesc.count == 2) // africa + lion
    }

    // MARK: - Cycle detection

    @Test("wouldCreateCycle detects self-loop")
    func selfLoop() {
        let tag = Tag(name: "A")
        #expect(TagGraphTraverser.wouldCreateCycle(adding: tag, to: tag) == true)
    }

    @Test("wouldCreateCycle detects cycle in chain")
    func chainCycle() {
        let a = Tag(name: "A")
        let b = Tag(name: "B")
        let c = Tag(name: "C")

        // A → B → C
        a.children.append(b); b.parents.append(a)
        b.children.append(c); c.parents.append(b)

        // Adding A as child of C would create C → A → B → C cycle
        #expect(TagGraphTraverser.wouldCreateCycle(adding: c, to: a) == true)
    }

    @Test("wouldCreateCycle returns false for valid edge")
    func noCycle() {
        let a = Tag(name: "A")
        let b = Tag(name: "B")
        // No edges yet — adding A as parent of B is valid
        #expect(TagGraphTraverser.wouldCreateCycle(adding: a, to: b) == false)
    }

    // MARK: - Path

    @Test("pathFromRoot returns correct breadcrumb")
    func breadcrumb() {
        let animals = Tag(name: "Animals")
        let mammals = Tag(name: "Mammals")
        let lion    = Tag(name: "Lion")

        mammals.parents.append(animals)
        animals.children.append(mammals)
        lion.parents.append(mammals)
        mammals.children.append(lion)

        let path = TagGraphTraverser.pathFromRoot(to: lion)
        #expect(path.map(\.name) == ["Animals", "Mammals", "Lion"])
    }
}

// MARK: - Tags experience tests

@Suite("Tags Experience", .serialized)
@MainActor
struct TagsExperienceTests {

    @Test("Tag icon catalog is complete, unique, categorized, and searchable")
    func iconCatalog() {
        #expect(TagIconCatalog.options.count == 96)
        #expect(Set(TagIconCatalog.options.map(\.systemName)).count == 96)

        for category in TagIconCategory.allCases {
            #expect(TagIconCatalog.options(in: category).count == 12)
        }

        #expect(TagIconCatalog.search("camera").contains { $0.systemName == "camera.fill" })
        #expect(TagIconCatalog.search("rupee").contains { $0.systemName == "indianrupeesign.circle.fill" })
        #expect(TagIconCatalog.search("finance").count == 12)
    }

    @Test("Search keeps matching paths and restores the previous expansion state")
    func searchPrunesAndRestoresExpansion() throws {
        let store = makeStore()
        let context = store.context
        let viewModel = store.viewModel
        let personal = Tag(name: "Personal")
        let work = Tag(name: "Work")
        let reports = Tag(name: "Reports")
        let expenses = Tag(name: "Expenses")

        work.children.append(reports)
        reports.children.append(expenses)
        context.insert(personal)
        context.insert(work)
        context.insert(reports)
        context.insert(expenses)
        try context.save()
        viewModel.reload()

        #expect(viewModel.rootTags.map(\.name) == ["Personal", "Work"])
        viewModel.expandedTagIDs = [personal.id]
        viewModel.setSearchText("expense")

        #expect(viewModel.filteredRootTags.map(\.name) == ["Work"])
        #expect(viewModel.matchingTagIDs == [expenses.id])
        #expect(viewModel.visibleChildren(of: work).map(\.name) == ["Reports"])
        #expect(viewModel.expandedTagIDs.contains(work.id))
        #expect(viewModel.expandedTagIDs.contains(reports.id))

        viewModel.setSearchText("")
        #expect(viewModel.expandedTagIDs == [personal.id])
    }

    @Test("Exact search matching ignores case and diacritics")
    func exactSearchMatching() throws {
        let store = makeStore()
        let context = store.context
        let viewModel = store.viewModel
        let cafe = Tag(name: "Café")
        context.insert(cafe)
        try context.save()
        viewModel.reload()

        viewModel.setSearchText("cafe")
        #expect(viewModel.hasExactSearchMatch)
    }

    @Test("Legacy multiple parents keep the alphabetically first parent")
    func normalizesMultipleParents() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let zebra = Tag(name: "Zebra")
        let alpha = Tag(name: "Alpha")
        let child = Tag(name: "Shared")

        zebra.children.append(child)
        alpha.children.append(child)
        context.insert(zebra)
        context.insert(alpha)
        context.insert(child)
        try context.save()

        let viewModel = KnowledgeViewModel()
        viewModel.setup(context: context)

        #expect(alpha.children.contains(where: { $0.id == child.id }))
        #expect(!zebra.children.contains(where: { $0.id == child.id }))
        #expect(viewModel.parent(of: child)?.id == alpha.id)
    }

    @Test("Moving replaces the parent, avoids duplicates, and prevents cycles")
    func moveRules() throws {
        let store = makeStore()
        let context = store.context
        let viewModel = store.viewModel
        let root = Tag(name: "Root")
        let branch = Tag(name: "Branch")
        let leaf = Tag(name: "Leaf")
        root.children.append(branch)
        branch.children.append(leaf)
        context.insert(root)
        context.insert(branch)
        context.insert(leaf)
        try context.save()
        viewModel.reload()

        #expect(viewModel.moveTag(leaf, to: root))
        #expect(!branch.children.contains(where: { $0.id == leaf.id }))
        #expect(root.children.filter { $0.id == leaf.id }.count == 1)

        #expect(viewModel.moveTag(leaf, to: root))
        #expect(root.children.filter { $0.id == leaf.id }.count == 1)

        #expect(!viewModel.moveTag(root, to: leaf))
        #expect(viewModel.errorMessage != nil)

        viewModel.clearError()
        #expect(viewModel.moveTag(branch, to: nil))
        #expect(viewModel.parent(of: branch) == nil)
    }

    @Test("Deleting a nested tag promotes children and preserves files")
    func deletePromotesChildren() throws {
        let store = makeStore()
        let context = store.context
        let viewModel = store.viewModel
        let root = Tag(name: "Root")
        let middle = Tag(name: "Middle")
        let child = Tag(name: "Child")
        let item = Item(title: "Document", fileType: .pdf)
        root.children.append(middle)
        middle.children.append(child)
        item.tags = [middle]

        context.insert(root)
        context.insert(middle)
        context.insert(child)
        context.insert(item)
        try context.save()
        viewModel.reload()

        #expect(viewModel.deleteTagPromotingChildren(middle))
        #expect(root.children.contains(where: { $0.id == child.id }))
        #expect(viewModel.parent(of: child)?.id == root.id)
        #expect(try context.fetchCount(FetchDescriptor<Findly.Tag>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 1)
    }

    @Test("Deleting a root tag promotes its children to the root")
    func deleteRootPromotesChildren() throws {
        let store = makeStore()
        let context = store.context
        let viewModel = store.viewModel
        let root = Tag(name: "Root")
        let child = Tag(name: "Child")
        root.children.append(child)
        context.insert(root)
        context.insert(child)
        try context.save()
        viewModel.reload()

        #expect(viewModel.deleteTagPromotingChildren(root))
        #expect(viewModel.rootTags.map(\.name) == ["Child"])
        #expect(viewModel.parent(of: child) == nil)
    }

    @MainActor
    private final class TestStore {
        let persistence: PersistenceController
        let context: ModelContext
        let viewModel: KnowledgeViewModel

        init() {
            persistence = PersistenceController(inMemory: true)
            context = persistence.container.mainContext
            viewModel = KnowledgeViewModel()
            viewModel.setup(context: context)
        }
    }

    private func makeStore() -> TestStore {
        TestStore()
    }
}

// MARK: - FileType detection tests

@Suite("FileType Detection")
struct FileTypeDetectionTests {

    @Test("detects image from extension")
    func imageExtension() {
        #expect(FileType.detect(fileExtension: "jpg")  == .image)
        #expect(FileType.detect(fileExtension: "png")  == .image)
        #expect(FileType.detect(fileExtension: "heic") == .image)
    }

    @Test("detects PDF from MIME type")
    func pdfMime() {
        #expect(FileType.detect(mimeType: "application/pdf") == .pdf)
    }

    @Test("fallback to other for unknown extension")
    func unknownExtension() {
        #expect(FileType.detect(fileExtension: "xyz123") == .other)
    }
}

// MARK: - Experimental features tests

@Suite("Experimental Features")
@MainActor
struct ExperimentalFeaturesTests {

    private static let alpha = ExperimentalFeature(
        id: "test.alpha",
        name: "Alpha",
        description: "First test fixture with a deliberately long description so the Settings toggle subtitle wraps across multiple lines at accessibility text sizes."
    )
    private static let beta = ExperimentalFeature(
        id: "test.beta",
        name: "Beta",
        description: "Second test fixture."
    )

    @Test("Every feature defaults to disabled when no preference exists")
    func defaultsToDisabled() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha, Self.beta]
        )

        #expect(!store.isEnabled(Self.alpha))
        #expect(!store.isEnabled(Self.beta))
        #expect(store.enabledCount == 0)
    }

    @Test("Empty catalog reports zero enabled features")
    func emptyCatalogIsZero() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExperimentalFeatureStore(defaults: defaults, features: [])

        #expect(store.allFeatures.isEmpty)
        #expect(store.enabledCount == 0)
        #expect(ExperimentalFeaturesSummary.text(enabledCount: store.enabledCount) == "Off")
    }

    @Test("Enabling and disabling a flag persists immediately")
    func enableAndDisable() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha, Self.beta]
        )

        store.setEnabled(true, for: Self.alpha)
        #expect(store.isEnabled(Self.alpha))
        #expect(store.enabledCount == 1)

        store.setEnabled(false, for: Self.alpha)
        #expect(!store.isEnabled(Self.alpha))
        #expect(store.enabledCount == 0)
    }

    @Test("Flags are independent of each other")
    func flagsAreIndependent() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha, Self.beta]
        )

        store.setEnabled(true, for: Self.alpha)

        #expect(store.isEnabled(Self.alpha))
        #expect(!store.isEnabled(Self.beta))
        #expect(store.enabledCount == 1)
    }

    @Test("Flags restore across relaunch from the same defaults suite")
    func relaunchRestoration() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstLaunch = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha, Self.beta]
        )
        firstLaunch.setEnabled(true, for: Self.alpha)
        firstLaunch.setEnabled(true, for: Self.beta)

        let secondLaunch = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha, Self.beta]
        )

        #expect(secondLaunch.isEnabled(Self.alpha))
        #expect(secondLaunch.isEnabled(Self.beta))
        #expect(secondLaunch.enabledCount == 2)
    }

    @Test("disableAll turns off every active flag")
    func disableAll() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha, Self.beta]
        )
        store.setEnabled(true, for: Self.alpha)
        store.setEnabled(true, for: Self.beta)

        store.disableAll()

        #expect(!store.isEnabled(Self.alpha))
        #expect(!store.isEnabled(Self.beta))
        #expect(store.enabledCount == 0)
    }

    @Test("Flags persist under a namespaced key")
    func namespacedPersistenceKey() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha]
        )

        store.setEnabled(true, for: Self.alpha)

        #expect(defaults.object(
            forKey: ExperimentalFeatureStore.key(for: Self.alpha.id)
        ) as? Bool == true)
    }

    @Test("Catalog IDs are unique")
    func catalogIDsAreUnique() {
        let ids = ExperimentalFeatureCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set([Self.alpha.id, Self.beta.id]).count == 2)
    }

    @Test("Unknown persisted IDs do not affect the app")
    func unknownPersistedIDsAreIgnored() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: ExperimentalFeatureStore.key(for: "removed-feature"))

        let store = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha]
        )

        #expect(store.enabledCount == 0)
        #expect(!store.allFeatures.contains { $0.id == "removed-feature" })
        #expect(!store.isEnabled(id: "removed-feature"))
    }

    @Test("Removed catalog entries stop contributing while survivors restore")
    func removedEntriesAreIgnored() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let beforeRemoval = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha, Self.beta]
        )
        beforeRemoval.setEnabled(true, for: Self.alpha)
        beforeRemoval.setEnabled(true, for: Self.beta)

        let afterRemoval = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha]
        )

        #expect(afterRemoval.isEnabled(Self.alpha))
        #expect(afterRemoval.enabledCount == 1)
        #expect(!afterRemoval.isEnabled(id: Self.beta.id))
    }

    @Test("Summary shows Off when nothing is enabled and counts otherwise")
    func enabledCountSummary() {
        #expect(ExperimentalFeaturesSummary.text(enabledCount: 0) == "Off")
        #expect(ExperimentalFeaturesSummary.text(enabledCount: 1) == "1 enabled")
        #expect(ExperimentalFeaturesSummary.text(enabledCount: 3) == "3 enabled")
    }

    @Test("Catalog registers Needs Attention with a stable ID, defaulting off")
    func needsAttentionRegistration() {
        let feature = ExperimentalFeatureCatalog.needsAttention

        #expect(feature.id == "needs-attention")
        #expect(!feature.name.isEmpty)
        #expect(!feature.description.isEmpty)
        #expect(!feature.defaultValue)
        #expect(ExperimentalFeatureCatalog.all.contains(feature))
        #expect(ExperimentalFeatureCatalog.all.map(\.id).contains("needs-attention"))
    }

    @Test("Needs Attention is disabled by default on a fresh install")
    func needsAttentionDefaultsOff() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Default init consults the real catalog, matching production wiring.
        let store = ExperimentalFeatureStore(defaults: defaults)

        #expect(!store.isEnabled(ExperimentalFeatureCatalog.needsAttention))
        #expect(store.enabledCount == 0)
        #expect(ExperimentalFeaturesSummary.text(enabledCount: store.enabledCount) == "Off")
    }

    @Test("Enabling Needs Attention through the registered catalog entry works")
    func needsAttentionOptIn() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExperimentalFeatureStore(defaults: defaults)

        store.setEnabled(true, for: ExperimentalFeatureCatalog.needsAttention)

        #expect(store.isEnabled(ExperimentalFeatureCatalog.needsAttention))
        #expect(store.enabledCount == 1)

        store.disableAll()

        #expect(!store.isEnabled(ExperimentalFeatureCatalog.needsAttention))
        #expect(store.enabledCount == 0)
    }

    @Test("Store notifies observers when a flag changes")
    func publishesFlagChanges() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha, Self.beta]
        )
        let counter = ObservationCounter()
        withObservationTracking {
            _ = store.isEnabled(Self.alpha)
        } onChange: {
            counter.count += 1
        }

        store.setEnabled(true, for: Self.alpha)

        // Delivery is asynchronous; wait briefly rather than asserting inline.
        for _ in 0..<100 where counter.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(counter.count >= 1)
    }

    @Test("Setting a flag to its current value does not notify observers")
    func noNotificationOnNoOp() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExperimentalFeatureStore(
            defaults: defaults,
            features: [Self.alpha]
        )
        store.setEnabled(true, for: Self.alpha)

        let counter = ObservationCounter()
        withObservationTracking {
            _ = store.isEnabled(Self.alpha)
        } onChange: {
            counter.count += 1
        }

        store.setEnabled(true, for: Self.alpha)
        try await Task.sleep(for: .milliseconds(100))
        #expect(counter.count == 0)
    }

    private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "ExperimentalFeaturesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }
}

/// Mutable box for observation callbacks, which may fire off the test actor.
private final class ObservationCounter {
    var count = 0
}
