import Foundation

/// Exports vault files as a ZIP archive without requiring a third-party library.
/// Uses ZIP STORE method (no compression — focus is on archiving, not size reduction).
///
/// The archive contains a `manifest.json` (all item/tag/search-history metadata) plus
/// one entry per file named `<UUID>.<ext>` and an optional `<UUID>_thumb.jpg` sidecar.
/// This layout is understood by `ImportService` for full-fidelity restore.
actor ExportService {
    // MARK: - Public interface

    /// Creates a ZIP archive of the full vault (files + metadata manifest) and returns its URL.
    /// The caller is responsible for deleting the temp file when done.
    @MainActor
    func exportVault(
        items: [Item],
        tags: [Tag],
        searchHistory: [SearchHistoryEntry],
        localStorage: LocalFileService,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let availableItems = items.filter(\.isAvailableForPresentation)
        // Snapshot metadata before suspending; later edits cannot change this archive.
        let manifest = buildManifest(items: availableItems, tags: tags, searchHistory: searchHistory)
        let thumbnails = Dictionary(uniqueKeysWithValues: availableItems.compactMap { item in
            item.thumbnailData.map { (item.id, $0) }
        })
        return try await writeArchive(manifest: manifest, thumbnails: thumbnails,
                                      localStorage: localStorage, onProgress: onProgress)
    }

    private func writeArchive(
        manifest: ExportManifest,
        thumbnails: [UUID: Data],
        localStorage: LocalFileService,
        onProgress: (@MainActor @Sendable (Double) -> Void)?
    ) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Findly_Export_\(UUID().uuidString).zip")

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)

        // Clean up the temp file if anything throws before we successfully return.
        var succeeded = false
        defer {
            if !succeeded { try? FileManager.default.removeItem(at: tempURL) }
        }

        let fileHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? fileHandle.close() }

        var writer = ZipWriter(fileHandle: fileHandle)

        // Every item must have a readable original, including items synced to Drive.
        // A cloud reference alone is not a self-contained backup.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try writer.addFile(name: "manifest.json", data: manifestData)

        // Pass 2: write each item's primary file and thumbnail sidecar.
        let total = max(1, manifest.items.count)
        var done = 0

        for item in manifest.items {
            try Task.checkCancellation()
            guard let relativePath = item.localFilePath,
                  ZipReader.isSafeFileName(relativePath) else {
                throw VaultBackupError.unavailable(item.title)
            }
            let url = await localStorage.fileURL(relativePath: relativePath)
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw VaultBackupError.unreadable(item.title, error.localizedDescription)
            }
            // Archive entry name == localFilePath so import can restore by path directly.
            try writer.addFile(name: relativePath, data: data)

            // Thumbnail lives only in SwiftData (@Attribute(.externalStorage)),
            // not as a sidecar file on disk — write it directly from the model.
            if let thumbData = thumbnails[item.id] {
                let thumbName = "\(item.id.uuidString)_thumb.jpg"
                try writer.addFile(name: thumbName, data: thumbData)
            }

            done += 1
            if let onProgress { await onProgress(Double(done) / Double(total)) }
        }

        try Task.checkCancellation()
        try writer.finalize()
        try fileHandle.synchronize()
        // Read back the completed archive before it can replace a previous backup.
        _ = try ZipReader(zipData: Data(contentsOf: tempURL)).validatedManifest()
        succeeded = true
        return tempURL
    }

    // MARK: - Manifest builder

    @MainActor
    private func buildManifest(
        items: [Item],
        tags: [Tag],
        searchHistory: [SearchHistoryEntry]
    ) -> ExportManifest {
        let exportTags = tags.map { tag in
            ExportTag(
                id: tag.id,
                name: tag.name,
                colorHex: tag.colorHex,
                sfSymbol: tag.sfSymbol,
                createdAt: tag.createdAt,
                parentIDs: tag.parents.map { $0.id }
            )
        }
        let exportItems = items.map { item in
            ExportItem(
                id: item.id,
                title: item.title,
                itemDescription: item.itemDescription,
                fileType: item.fileType,
                fileSize: item.fileSize,
                originalFileName: item.originalFileName,
                localFilePath: item.localFilePath,
                googleDriveFileID: item.googleDriveFileID,
                syncStatus: item.syncStatus,
                createdAt: item.createdAt,
                modifiedAt: item.modifiedAt,
                lastOpenedAt: item.lastOpenedAt,
                viewCount: item.viewCount,
                isFavorite: item.isFavorite,
                isPinned: item.isPinned,
                tagIDs: item.tags.map { $0.id }
            )
        }
        let exportHistory = searchHistory.map { entry in
            ExportSearchHistoryEntry(
                id: entry.id,
                query: entry.query,
                timestamp: entry.timestamp,
                useCount: entry.useCount
            )
        }
        return ExportManifest(
            version: 1,
            exportedAt: Date(),
            items: exportItems,
            tags: exportTags,
            searchHistory: exportHistory
        )
    }
}

enum VaultBackupError: LocalizedError {
    case unavailable(String)
    case unreadable(String, String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let title):
            return "Backup incomplete: the original file for ‘\(title)’ is unavailable. Restore or download it before backing up. The previous backup has not been replaced."
        case .unreadable(let title, let reason):
            return "Backup incomplete: could not read ‘\(title)’. \(reason) The previous backup has not been replaced."
        }
    }
}

// MARK: - Manifest types

struct ExportManifest: Codable {
    let version: Int
    let exportedAt: Date
    let items: [ExportItem]
    let tags: [ExportTag]
    let searchHistory: [ExportSearchHistoryEntry]
}

struct ExportItem: Codable {
    let id: UUID
    let title: String
    let itemDescription: String
    let fileType: FileType
    let fileSize: Int64
    let originalFileName: String
    let localFilePath: String?
    let googleDriveFileID: String?
    let syncStatus: SyncStatus
    let createdAt: Date
    let modifiedAt: Date
    let lastOpenedAt: Date?
    let viewCount: Int
    let isFavorite: Bool
    let isPinned: Bool
    let tagIDs: [UUID]
}

struct ExportTag: Codable {
    let id: UUID
    let name: String
    let colorHex: String
    let sfSymbol: String
    let createdAt: Date
    let parentIDs: [UUID]
}

struct ExportSearchHistoryEntry: Codable {
    let id: UUID
    let query: String
    let timestamp: Date
    let useCount: Int
}

// MARK: - Errors

enum ZipError: Error, LocalizedError {
    case tooManyFiles
    case archiveTooLarge

    var errorDescription: String? {
        switch self {
        case .tooManyFiles:
            return "ZIP export supports at most 65,535 files. Please export a smaller selection."
        case .archiveTooLarge:
            return "The vault exceeds the 4 GB ZIP limit. Please remove some large files before exporting."
        }
    }
}

// MARK: - Streaming ZIP writer (STORE, no compression)
//
// Writes local file headers and data directly to a FileHandle so peak memory usage
// is one file at a time. The central directory entries are tracked in memory but are
// tiny (metadata only).

private struct ZipWriter {

    private let fileHandle: FileHandle
    private var entries: [EntryMeta] = []
    // Int (64-bit on all Apple platforms) to detect 4 GB overflow before it corrupts the archive.
    private var currentOffset: Int = 0

    private struct EntryMeta {
        let name: Data       // UTF-8 encoded filename
        let dataSize: UInt32
        let crc32: UInt32
        let offset: UInt32   // byte offset of local file header in the output file
    }

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    // MARK: - Add file

    mutating func addFile(name: String, data: Data) throws {
        // Guard against 4 GB overflow before writing anything.
        guard currentOffset <= Int(UInt32.max), data.count <= Int(UInt32.max) else {
            throw ZipError.archiveTooLarge
        }

        let nameData = name.data(using: .utf8) ?? Data()
        let crc = crc32(data)
        let offset = UInt32(currentOffset)

        // Build local file header (30 bytes fixed + filename).
        var header = Data()
        appendUInt32(0x04034b50, to: &header)            // PK\x03\x04
        appendUInt16(20, to: &header)                     // version needed
        appendUInt16(0x0800, to: &header)                 // UTF-8 flag (bit 11)
        appendUInt16(0, to: &header)                      // compression: STORE
        appendUInt16(dosTime(), to: &header)
        appendUInt16(dosDate(), to: &header)
        appendUInt32(crc, to: &header)
        appendUInt32(UInt32(data.count), to: &header)     // compressed size = uncompressed (STORE)
        appendUInt32(UInt32(data.count), to: &header)     // uncompressed size
        appendUInt16(UInt16(nameData.count), to: &header)
        appendUInt16(0, to: &header)                      // extra field length

        try fileHandle.write(contentsOf: header)
        try fileHandle.write(contentsOf: nameData)
        try fileHandle.write(contentsOf: data)

        currentOffset += header.count + nameData.count + data.count
        entries.append(EntryMeta(name: nameData, dataSize: UInt32(data.count), crc32: crc, offset: offset))
    }

    // MARK: - Finalize (writes central directory + EOCD)

    mutating func finalize() throws {
        guard entries.count <= 65_535 else { throw ZipError.tooManyFiles }
        guard currentOffset <= Int(UInt32.max) else { throw ZipError.archiveTooLarge }

        let centralDirStart = UInt32(currentOffset)
        var centralDirSize: UInt32 = 0
        var centralDir = Data()

        for entry in entries {
            appendUInt32(0x02014b50, to: &centralDir)     // central directory signature
            appendUInt16(20, to: &centralDir)              // version made by
            appendUInt16(20, to: &centralDir)              // version needed
            appendUInt16(0x0800, to: &centralDir)          // UTF-8 flag
            appendUInt16(0, to: &centralDir)               // compression: STORE
            appendUInt16(dosTime(), to: &centralDir)
            appendUInt16(dosDate(), to: &centralDir)
            appendUInt32(entry.crc32, to: &centralDir)
            appendUInt32(entry.dataSize, to: &centralDir)
            appendUInt32(entry.dataSize, to: &centralDir)
            appendUInt16(UInt16(entry.name.count), to: &centralDir)
            appendUInt16(0, to: &centralDir)               // extra length
            appendUInt16(0, to: &centralDir)               // comment length
            appendUInt16(0, to: &centralDir)               // disk number start
            appendUInt16(0, to: &centralDir)               // internal attrs
            appendUInt32(0, to: &centralDir)               // external attrs
            appendUInt32(entry.offset, to: &centralDir)
            centralDir.append(entry.name)
            centralDirSize += 46 + UInt32(entry.name.count)
        }

        // End of central directory record.
        var eocd = Data()
        appendUInt32(0x06054b50, to: &eocd)
        appendUInt16(0, to: &eocd)                         // disk number
        appendUInt16(0, to: &eocd)                         // disk with central dir
        appendUInt16(UInt16(entries.count), to: &eocd)
        appendUInt16(UInt16(entries.count), to: &eocd)
        appendUInt32(centralDirSize, to: &eocd)
        appendUInt32(centralDirStart, to: &eocd)
        appendUInt16(0, to: &eocd)                         // comment length

        try fileHandle.write(contentsOf: centralDir)
        try fileHandle.write(contentsOf: eocd)
    }

    // MARK: - Helpers

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private func dosTime() -> UInt16 {
        let c = Calendar.current
        let now = Date()
        let h = UInt16(c.component(.hour, from: now))
        let m = UInt16(c.component(.minute, from: now))
        let s = UInt16(c.component(.second, from: now))
        return (h << 11) | (m << 5) | (s / 2)
    }

    private func dosDate() -> UInt16 {
        let c = Calendar.current
        let now = Date()
        let y = UInt16(c.component(.year, from: now)) - 1980
        let mo = UInt16(c.component(.month, from: now))
        let d = UInt16(c.component(.day, from: now))
        return (y << 9) | (mo << 5) | d
    }

    // Standard CRC-32 (ISO 3309 / ITU-T V.42) — same polynomial used by zlib.
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            var b = UInt32(byte) ^ (crc & 0xFF)
            for _ in 0..<8 {
                b = (b & 1 == 0) ? b >> 1 : (b >> 1) ^ 0xEDB8_8320
            }
            crc = b ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
