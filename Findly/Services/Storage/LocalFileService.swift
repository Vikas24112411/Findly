import Foundation

/// Actor-isolated on-device file storage.
///
/// Files are stored at `{baseDirectory}/{uuid}.{ext}`.
/// The base directory is supplied at init time by `StorageLocationService`
/// and can be changed at runtime via `updateBaseDirectory(_:)` (onboarding,
/// no existing files) or `migrateToDirectory(_:)` (Settings, copies files).
///
/// **iCloud exclusion:** Each base directory is excluded from iCloud backup on
/// first use — Google Drive serves as the authoritative backup mechanism.
actor LocalFileService {

    // MARK: - Base directory

    private(set) var baseDirectory: URL

    init(baseDirectory: URL) throws {
        self.baseDirectory = baseDirectory
        try Self.setupDirectory(baseDirectory)
    }

    // MARK: - Change base directory (no file copying)

    /// Switches the base directory without moving any files.
    /// Use this during first-launch onboarding when no files exist yet.
    func updateBaseDirectory(_ newURL: URL) throws {
        try Self.setupDirectory(newURL)
        baseDirectory = newURL
    }

    // MARK: - Migrate (copy files to new directory)

    /// Copies all files from the current base directory to `newURL`,
    /// updates `baseDirectory`, and returns the old URL so the caller
    /// can delete it after confirming success.
    @discardableResult
    func migrateToDirectory(_ newURL: URL) throws -> URL {
        try Self.setupDirectory(newURL)

        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        for file in contents {
            let dest = newURL.appending(component: file.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: file, to: dest)
        }

        let oldDirectory = baseDirectory
        baseDirectory = newURL
        return oldDirectory
    }

    // MARK: - Write

    /// Saves `data` to disk and returns the relative path (e.g. `"abc123.pdf"`).
    func write(data: Data, itemID: UUID, fileExtension: String) throws -> String {
        let fileName = "\(itemID.uuidString).\(fileExtension)"
        let url = baseDirectory.appending(component: fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    /// Copies a file from `sourceURL` to the vault directory and returns the relative path.
    /// Use this instead of `write(data:)` for large files (e.g. videos) to avoid loading
    /// the entire file into memory.
    func write(from sourceURL: URL, itemID: UUID, fileExtension: String) throws -> String {
        let fileName = "\(itemID.uuidString).\(fileExtension)"
        let destURL = baseDirectory.appending(component: fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
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

    // MARK: - Private helpers

    private static func setupDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var dirURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try dirURL.setResourceValues(resourceValues)
    }
}
