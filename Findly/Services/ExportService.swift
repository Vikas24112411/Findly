import Foundation
import zlib

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
        // Progress is weighted by bytes, not item count, so one large video does
        // not look like a stall. Writing fills the first part of the bar and the
        // read-back verification fills the rest; 100% is only sent on return.
        let relay = ProgressRelay(onProgress)
        let writeShare = 0.7
        let total = max(1, manifest.items.count)
        let totalBytes = manifest.items.reduce(Int64(0)) { $0 + max(0, $1.fileSize) }
        var done = 0
        var doneBytes: Int64 = 0

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
            doneBytes += Int64(data.count)
            let fraction = totalBytes > 0
                ? min(1, Double(doneBytes) / Double(totalBytes))
                : Double(done) / Double(total)
            relay.report(fraction * writeShare)
        }

        try Task.checkCancellation()
        try writer.finalize()
        try fileHandle.synchronize()
        // Read back the completed archive before it can replace a previous backup.
        // Memory-mapped so the archive is checksummed without loading it all into RAM.
        let reader = ZipReader(zipData: try Data(contentsOf: tempURL, options: .mappedIfSafe))
        let entries = try reader.entries { relay.report(writeShare + $0 * (1 - writeShare)) }
        _ = try reader.validatedManifest(entries: entries)
        succeeded = true
        await relay.finish()
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
        let crc = ZipChecksum.crc32(data)
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
}

// MARK: - CRC-32

/// Standard CRC-32 (ISO 3309 / ITU-T V.42) via the system zlib, which is
/// hardware-accelerated — orders of magnitude faster than a bitwise loop.
enum ZipChecksum {
    static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> UInt32 in
            var crc = zlib.crc32(0, nil, 0)
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
                return UInt32(truncatingIfNeeded: crc)
            }
            var offset = 0
            while offset < buffer.count {
                // zlib takes a 32-bit length; feed large buffers in pieces.
                let length = min(buffer.count - offset, 1 << 30)
                crc = zlib.crc32(crc, base + offset, uInt(length))
                offset += length
            }
            return UInt32(truncatingIfNeeded: crc)
        }
    }
}

// MARK: - Progress relay

/// Forwards progress from background work to a main-actor handler.
///
/// - Throttled to whole-percent steps so tight loops do not flood the main actor.
/// - Never moves backwards.
/// - Holds at 99% until `finish()` so the UI only shows 100% once the work is done.
final class ProgressRelay: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (Double) -> Void

    private let handler: Handler?
    private let lock = NSLock()
    private var lastQueued = -1.0
    @MainActor private var delivered = -1.0
    @MainActor private var finished = false

    init(_ handler: Handler?) {
        self.handler = handler
    }

    /// Safe to call from any thread.
    func report(_ value: Double) {
        guard handler != nil else { return }
        let clamped = min(max(value, 0), 0.99)
        lock.lock()
        let shouldSend = clamped - lastQueued >= 0.01
        if shouldSend { lastQueued = clamped }
        lock.unlock()
        guard shouldSend else { return }
        Task { @MainActor in self.deliver(clamped) }
    }

    @MainActor
    func finish() {
        guard !finished else { return }
        finished = true
        handler?(1)
    }

    @MainActor
    private func deliver(_ value: Double) {
        guard !finished, value > delivered else { return }
        delivered = value
        handler?(value)
    }
}
