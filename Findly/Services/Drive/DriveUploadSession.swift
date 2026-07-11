import Foundation

/// Handles resumable uploads for files larger than 5 MB using the
/// Google Drive resumable upload protocol.
///
/// Reference: https://developers.google.com/drive/api/guides/manage-uploads#resumable
actor DriveUploadSession {

    private let uploadBase = "https://www.googleapis.com/upload/drive/v3"
    private let chunkSize  = 256 * 1024  // 256 KB — minimum per Google spec

    private let auth: AuthService
    private let urlSession: URLSession

    init(auth: AuthService, urlSession: URLSession = .shared) {
        self.auth = auth
        self.urlSession = urlSession
    }

    // MARK: - Upload

    func upload(
        data: Data,
        fileName: String,
        mimeType: String,
        parentID: String,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> String {
        let locationURL = try await initiateSession(
            fileName: fileName,
            mimeType: mimeType,
            parentID: parentID,
            totalBytes: data.count
        )
        return try await uploadChunks(
            data: data,
            locationURL: locationURL,
            mimeType: mimeType,
            onProgress: onProgress
        )
    }

    // MARK: - Session initiation

    private func initiateSession(
        fileName: String,
        mimeType: String,
        parentID: String,
        totalBytes: Int
    ) async throws -> URL {
        let token = try await auth.freshAccessToken()
        let metadata = DriveFileMetadata(name: fileName, mimeType: mimeType, parents: [parentID])

        var comps = URLComponents(string: "\(uploadBase)/files")!
        comps.queryItems = [.init(name: "uploadType", value: "resumable")]

        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue("\(totalBytes)", forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONEncoder().encode(metadata)

        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let locationString = http.value(forHTTPHeaderField: "Location"),
              let locationURL = URL(string: locationString)
        else {
            throw DriveAPIError.uploadFailed("Could not initiate resumable session.")
        }
        return locationURL
    }

    // MARK: - Chunked upload

    private func uploadChunks(
        data: Data,
        locationURL: URL,
        mimeType: String,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> String {
        let total = data.count
        var offset = 0

        while offset < total {
            let end = min(offset + chunkSize, total)
            let chunk = data[offset..<end]
            let range = "bytes \(offset)-\(end - 1)/\(total)"

            var request = URLRequest(url: locationURL)
            request.httpMethod = "PUT"
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            request.setValue("\(chunk.count)", forHTTPHeaderField: "Content-Length")
            request.setValue(range, forHTTPHeaderField: "Content-Range")
            request.httpBody = Data(chunk)

            let (responseData, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DriveAPIError.uploadFailed("No HTTP response during chunk upload.")
            }

            // 308 Resume Incomplete — chunk accepted, continue
            // 200/201 — upload complete
            switch http.statusCode {
            case 200, 201:
                let file = try JSONDecoder().decode(DriveUploadResponse.self, from: responseData)
                onProgress(1.0)
                return file.id
            case 308:
                offset = end
                onProgress(Double(end) / Double(total))
            default:
                throw DriveAPIError.httpError(http.statusCode,
                    HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
            }
        }
        throw DriveAPIError.uploadFailed("Upload ended without a completion response.")
    }
}
