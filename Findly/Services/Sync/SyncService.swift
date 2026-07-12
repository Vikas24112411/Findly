import Foundation
import SwiftData

/// Orchestrates synchronization between local SwiftData storage and Google Drive.
///
/// Google Drive is **optional**. When not connected, items are stored locally
/// with `.localOnly` status and no upload is attempted. When Drive is connected,
/// call `promoteLocalOnlyItems()` to queue them for upload, then `syncPendingItems()`.
@Observable
@MainActor
final class SyncService {

    // MARK: - State

    private(set) var isSyncing: Bool = false
    private(set) var lastSyncDate: Date?
    private(set) var pendingCount: Int = 0
    private(set) var lastError: Error?

    // MARK: - Dependencies

    private let drive: GoogleDriveService
    private let auth: AuthService
    private let localStorage: LocalFileService
    private let queue: SyncQueue
    private let context: ModelContext

    // MARK: - Init

    init(drive: GoogleDriveService, auth: AuthService, localStorage: LocalFileService, context: ModelContext) {
        self.drive = drive
        self.auth = auth
        self.localStorage = localStorage
        self.queue = SyncQueue()
        self.context = context
    }

    // MARK: - Sync pending items (upload direction)

    /// Uploads all items with `.pending` or `.failed` syncStatus to Google Drive.
    /// No-op if Drive is not connected. Safe to call concurrently.
    func syncPendingItems() async {
        guard auth.isAuthenticated else { return }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Note: SwiftData #Predicate does not support enum case comparisons,
        // so we fetch all items and filter in memory.
        let pendingItems: [Item]
        do {
            let all = try context.fetch(FetchDescriptor<Item>())
            pendingItems = all.filter { $0.syncStatus == .pending || $0.syncStatus == .failed }
        } catch {
            lastError = error
            return
        }

        pendingCount = pendingItems.count
        guard !pendingItems.isEmpty else {
            lastSyncDate = Date()
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for item in pendingItems {
                let itemID = item.id
                group.addTask { [self] in
                    guard await self.queue.claim(itemID) else { return }
                    await self.upload(itemID: itemID)
                    await self.queue.release(itemID)
                }
            }
        }

        pendingCount = 0
        lastSyncDate = Date()
        // Persist so SettingsView.lastSyncDate (which reads UserDefaults) reflects auto-syncs too.
        UserDefaults.standard.set(Date(), forKey: "lastSyncDate")
    }

    // MARK: - Promote local-only items when Drive is first connected

    /// Changes all `.localOnly` items to `.pending` so they will be uploaded
    /// on the next `syncPendingItems()` call.
    /// Call this immediately after the user successfully connects Google Drive.
    func promoteLocalOnlyItems() {
        let localOnlyItems = ((try? context.fetch(FetchDescriptor<Item>())) ?? [])
            .filter { $0.syncStatus == .localOnly }
        localOnlyItems.forEach { $0.syncStatus = .pending }
        try? context.save()
        pendingCount = localOnlyItems.count
    }

    // MARK: - Upload a single item

    private func upload(itemID: UUID) async {
        guard let item = fetchItem(id: itemID) else { return }

        guard let relativePath = item.localFilePath else {
            item.syncStatus = .failed
            try? context.save()
            return
        }

        item.syncStatus = .syncing
        try? context.save()

        do {
            let data = try await localStorage.read(relativePath: relativePath)
            let driveID = try await drive.upload(
                data: data,
                fileName: item.originalFileName.isEmpty
                    ? "\(item.title).\(item.fileType.fileExtension)"
                    : item.originalFileName,
                mimeType: item.fileType.primaryMimeType
            )
            item.googleDriveFileID = driveID
            item.syncStatus = .synced
            item.modifiedAt = Date()
            do { try context.save() } catch { lastError = error }
        } catch AuthError.notSignedIn {
            // Drive was disconnected mid-upload; revert to localOnly (not an error)
            item.syncStatus = .localOnly
            try? context.save()
        } catch {
            item.syncStatus = .failed
            lastError = error
            try? context.save()
        }
    }

    // MARK: - Recovery (Drive → local)

    /// Re-downloads a file from Drive and restores it to local storage.
    func recoverFromDrive(item: Item) async throws {
        guard auth.isAuthenticated else { throw SyncError.notAuthenticated }
        guard let driveID = item.googleDriveFileID else { throw SyncError.noRemoteFile }

        let data = try await drive.downloadFile(driveFileID: driveID)
        let path = try await localStorage.write(data: data, itemID: item.id, fileExtension: item.fileType.fileExtension)

        item.localFilePath = path
        item.syncStatus = .synced
        item.modifiedAt = Date()
        try context.save()
    }

    // MARK: - Helpers

    private func fetchItem(id: UUID) -> Item? {
        try? context.fetch(FetchDescriptor<Item>(
            predicate: #Predicate { $0.id == id }
        )).first
    }
}

// MARK: - SyncError

enum SyncError: LocalizedError {
    case notAuthenticated
    case noLocalFile
    case noRemoteFile
    case uploadCancelled

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Please connect Google Drive in Settings to sync."
        case .noLocalFile:      return "Local file is missing. Please re-add the item."
        case .noRemoteFile:     return "No Google Drive file ID found. The item has not been uploaded yet."
        case .uploadCancelled:  return "Upload was cancelled."
        }
    }
}
