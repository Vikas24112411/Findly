import Foundation

// MARK: - Drive REST API response DTOs

struct DriveFile: Codable, Sendable {
    let id: String
    let name: String
    let mimeType: String
    /// Drive returns file sizes as strings.
    let size: String?
    let createdTime: String?
    let modifiedTime: String?
    let parents: [String]?
    let webContentLink: String?

    var sizeBytes: Int64 {
        Int64(size ?? "0") ?? 0
    }
}

struct DriveFileList: Codable, Sendable {
    let files: [DriveFile]
    let nextPageToken: String?
}

struct DriveUploadResponse: Codable, Sendable {
    let id: String
    let name: String
    let mimeType: String
}

struct DriveError: Codable, Sendable {
    struct Detail: Codable {
        let code: Int
        let message: String
        let status: String?
    }
    let error: Detail
}

// MARK: - Metadata for creating/uploading files

struct DriveFileMetadata: Codable, Sendable {
    let name: String
    let mimeType: String
    let parents: [String]?

    init(name: String, mimeType: String, parents: [String]? = nil) {
        self.name = name
        self.mimeType = mimeType
        self.parents = parents
    }
}

// MARK: - Drive API errors

enum DriveAPIError: LocalizedError {
    case notAuthenticated
    case httpError(Int, String)
    case decodingError(Error)
    case uploadFailed(String)
    case noFolderID
    case fileMissing

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:        return "Not signed in to Google Drive."
        case .httpError(let c, let m): return "Drive API error \(c): \(m)"
        case .decodingError(let e):    return "Failed to parse Drive response: \(e.localizedDescription)"
        case .uploadFailed(let m):     return "Upload failed: \(m)"
        case .noFolderID:              return "Could not locate or create the Findly folder in Drive."
        case .fileMissing:             return "File not found on Google Drive."
        }
    }
}
