import Foundation

enum SyncStatus: String, Codable, Sendable {
    /// Google Drive not connected; file lives on-device only. Not an error state.
    case localOnly
    /// Drive connected; queued for upload.
    case pending
    /// Upload is currently in progress.
    case syncing
    /// Successfully uploaded; `googleDriveFileID` is set.
    case synced
    /// Last upload attempt failed; will be retried when Drive is connected.
    case failed

    var displayLabel: String {
        switch self {
        case .localOnly: return "On Device"
        case .pending:   return "Pending"
        case .syncing:   return "Syncing"
        case .synced:    return "Synced"
        case .failed:    return "Failed"
        }
    }

    var sfSymbol: String {
        switch self {
        case .localOnly: return "iphone"
        case .pending:   return "clock"
        case .syncing:   return "arrow.triangle.2.circlepath"
        case .synced:    return "checkmark.icloud.fill"
        case .failed:    return "exclamationmark.icloud.fill"
        }
    }

    var isTerminal: Bool {
        self == .synced
    }

    /// Items that should be uploaded when Drive becomes available.
    var needsUpload: Bool {
        self == .localOnly || self == .pending || self == .failed
    }

    /// Items that should be retried when Drive is already connected.
    var needsRetry: Bool {
        self == .pending || self == .failed
    }
}
