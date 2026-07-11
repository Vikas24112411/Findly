import Foundation

/// Actor-isolated on-device file storage.
///
/// Files are stored at: `{AppSupport}/Findly/files/{uuid}.{ext}`
///
/// Using `AppSupport` (not `Caches`) ensures files survive app updates and
/// are not purged by the OS. Google Drive acts as the authoritative backup.
///
/// **iCloud exclusion:** The `Findly/files/` directory is excluded from
/// iCloud backup on first use — Google Drive is the backup mechanism.
actor LocalFileService {

    // MARK: - Base directory

    private let baseDirectory: URL

    init() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        baseDirectory = support.appending(components: "Findly", "files")
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        // Exclude from iCloud backup
        var url = baseDirectory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
    }

    // MARK: - Write

    /// Saves `data` to disk and returns the relative path (e.g. `"abc123.pdf"`).
    func write(data: Data, itemID: UUID, fileExtension: String) throws -> String {
        let fileName = "\(itemID.uuidString).\(fileExtension)"
        let url = baseDirectory.appending(component: fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    // MARK: - Read

    func read(relativePath: String) throws -> Data {
        let url = fileURL(relativePath: relativePath)
        return try Data(contentsOf: url)
    }

    // MARK: - URL

    func fileURL(relativePath: String) -> URL {
        baseDirectory.appending(component: relativePath)
    }

    // MARK: - Existence

    func exists(relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(relativePath: relativePath).path)
    }

    // MARK: - Delete

    func delete(relativePath: String) throws {
        let url = fileURL(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Size

    func sizeOfLocalStorage() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: - Thumbnail write / read

    func writeThumbnail(data: Data, itemID: UUID) throws -> String {
        let fileName = "\(itemID.uuidString)_thumb.jpg"
        let url = baseDirectory.appending(component: fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }
}
