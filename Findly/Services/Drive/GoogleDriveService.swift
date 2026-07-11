import Foundation

/// Actor that wraps the Google Drive v3 REST API using `URLSession`.
///
/// All state mutations (e.g. caching `appFolderID`) are automatically
/// serialized by the actor runtime.
///
/// **Scope:** `drive.file` — only accesses files created by this app.
actor GoogleDriveService {

    // MARK: - Constants

    private let apiBase    = "https://www.googleapis.com/drive/v3"
    private let uploadBase = "https://www.googleapis.com/upload/drive/v3"
    private let appFolderName = "Findly"

    // MARK: - Dependencies

    private let auth: AuthService
    private let session: URLSession

    // MARK: - Cached state

    private var appFolderID: String?

    // MARK: - Init

    init(auth: AuthService, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: - App folder

    /// Returns the Findly folder ID, creating it if necessary.
    func appFolder() async throws -> String {
        if let id = appFolderID { return id }
        let id = try await findOrCreateAppFolder()
        appFolderID = id
        return id
    }

    private func findOrCreateAppFolder() async throws -> String {
        // Search for existing folder
        var comps = URLComponents(string: "\(apiBase)/files")!
        comps.queryItems = [
            .init(name: "q", value: "name='\(appFolderName)' and mimeType='application/vnd.google-apps.folder' and trashed=false"),
            .init(name: "fields", value: "files(id,name)"),
            .init(name: "spaces", value: "drive")
        ]
        let request = try await authorizedRequest(url: comps.url!)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let list = try decode(DriveFileList.self, from: data)
        if let existing = list.files.first { return existing.id }

        // Create the folder
        let metadata = DriveFileMetadata(
            name: appFolderName,
            mimeType: "application/vnd.google-apps.folder"
        )
        var create = try await authorizedRequest(url: URL(string: "\(apiBase)/files")!, method: "POST")
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        create.httpBody = try JSONEncoder().encode(metadata)
        let (createData, createResponse) = try await session.data(for: create)
        try validate(createResponse)
        let folder = try decode(DriveFile.self, from: createData)
        return folder.id
    }

    // MARK: - Upload

    /// Uploads `data` to the Findly Drive folder.
    /// Files ≤ 5 MB use multipart upload; larger files use resumable upload.
    func upload(
        data: Data,
        fileName: String,
        mimeType: String,
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> String {
        let folderID = try await appFolder()
        if data.count <= 5 * 1024 * 1024 {
            return try await multipartUpload(data: data, fileName: fileName, mimeType: mimeType, parentID: folderID)
        } else {
            let session = DriveUploadSession(auth: auth, urlSession: self.session)
            return try await session.upload(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                parentID: folderID,
                onProgress: onProgress
            )
        }
    }

    // MARK: - Multipart upload (≤5 MB)

    private func multipartUpload(
        data: Data,
        fileName: String,
        mimeType: String,
        parentID: String
    ) async throws -> String {
        let boundary = "FindlyBoundary-\(UUID().uuidString)"
        let metadata = DriveFileMetadata(name: fileName, mimeType: mimeType, parents: [parentID])

        var body = Data()
        body.appendString("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(try JSONEncoder().encode(metadata))
        body.appendString("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendString("\r\n--\(boundary)--")

        var comps = URLComponents(string: "\(uploadBase)/files")!
        comps.queryItems = [.init(name: "uploadType", value: "multipart")]
        var request = try await authorizedRequest(url: comps.url!, method: "POST")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        try validate(response)
        let file = try decode(DriveUploadResponse.self, from: responseData)
        return file.id
    }

    // MARK: - Download

    /// Downloads a file by Drive ID and returns its raw bytes.
    func downloadFile(driveFileID: String) async throws -> Data {
        var comps = URLComponents(string: "\(apiBase)/files/\(driveFileID)")!
        comps.queryItems = [.init(name: "alt", value: "media")]
        let request = try await authorizedRequest(url: comps.url!)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    // MARK: - Metadata

    func fileMetadata(driveFileID: String) async throws -> DriveFile {
        var comps = URLComponents(string: "\(apiBase)/files/\(driveFileID)")!
        comps.queryItems = [.init(name: "fields", value: "id,name,mimeType,size,createdTime,modifiedTime")]
        let request = try await authorizedRequest(url: comps.url!)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decode(DriveFile.self, from: data)
    }

    // MARK: - Delete

    func deleteFile(driveFileID: String) async throws {
        let url = URL(string: "\(apiBase)/files/\(driveFileID)")!
        let request = try await authorizedRequest(url: url, method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    // MARK: - List folder contents

    func listAppFolder() async throws -> [DriveFile] {
        let folderID = try await appFolder()
        var comps = URLComponents(string: "\(apiBase)/files")!
        comps.queryItems = [
            .init(name: "q", value: "'\(folderID)' in parents and trashed=false"),
            .init(name: "fields", value: "files(id,name,mimeType,size,modifiedTime)"),
            .init(name: "orderBy", value: "modifiedTime desc")
        ]
        let request = try await authorizedRequest(url: comps.url!)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let list = try decode(DriveFileList.self, from: data)
        return list.files
    }

    // MARK: - Storage quota

    func storageQuota() async throws -> (used: Int64, total: Int64) {
        var comps = URLComponents(string: "\(apiBase)/about")!
        comps.queryItems = [.init(name: "fields", value: "storageQuota")]
        let request = try await authorizedRequest(url: comps.url!)
        let (data, response) = try await session.data(for: request)
        try validate(response)

        struct About: Codable {
            struct Quota: Codable { let usage: String?; let limit: String? }
            let storageQuota: Quota
        }
        let about = try decode(About.self, from: data)
        let used  = Int64(about.storageQuota.usage ?? "0") ?? 0
        let total = Int64(about.storageQuota.limit ?? "0") ?? 0
        return (used, total)
    }

    // MARK: - Helpers

    private func authorizedRequest(url: URL, method: String = "GET") async throws -> URLRequest {
        let token = try await auth.freshAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw DriveAPIError.httpError(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw DriveAPIError.decodingError(error)
        }
    }
}

// MARK: - Data helper

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
