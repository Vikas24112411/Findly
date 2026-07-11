import Foundation
import SwiftData

@Model
final class Item {

    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    var title: String

    // 'description' conflicts with CustomStringConvertible; using itemDescription instead.
    var itemDescription: String

    // MARK: - File info

    var fileType: FileType
    var fileSize: Int64
    var originalFileName: String

    // MARK: - Storage

    /// Relative path within AppSupport/Findly/files/ — set immediately on save.
    var localFilePath: String?

    /// Google Drive file ID — set after successful upload.
    var googleDriveFileID: String?

    /// Sync state with Google Drive.
    var syncStatus: SyncStatus

    // MARK: - Thumbnail

    /// Stored externally (large binary) to keep the main SQLite store lean.
    @Attribute(.externalStorage)
    var thumbnailData: Data?

    // MARK: - Timestamps

    var createdAt: Date
    var modifiedAt: Date
    var lastOpenedAt: Date?

    // MARK: - Engagement

    var viewCount: Int
    var isFavorite: Bool
    var isPinned: Bool

    // MARK: - Tags (many-to-many, inverse declared on Tag.items)

    @Relationship(deleteRule: .nullify, inverse: \Tag.items)
    var tags: [Tag]

    // MARK: - Init

    init(
        id: UUID = UUID(),
        title: String,
        fileType: FileType,
        fileSize: Int64 = 0,
        originalFileName: String = ""
    ) {
        self.id = id
        self.title = title
        self.itemDescription = ""
        self.fileType = fileType
        self.fileSize = fileSize
        self.originalFileName = originalFileName
        self.syncStatus = .pending
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.viewCount = 0
        self.isFavorite = false
        self.isPinned = false
        self.tags = []
    }

    // MARK: - Computed helpers

    var localFileAvailable: Bool { localFilePath != nil }
    var isUploaded: Bool         { googleDriveFileID != nil }
    var isSynced: Bool           { syncStatus == .synced }

    /// Returns a concise subtitle for list/card views.
    var subtitle: String {
        var parts: [String] = []
        parts.append(fileSize.fileSizeString)
        parts.append(createdAt.shortRelativeString)
        if !tags.isEmpty {
            parts.append(tags.prefix(2).map(\.name).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    func markOpened() {
        viewCount += 1
        lastOpenedAt = Date()
        modifiedAt = Date()
    }
}
