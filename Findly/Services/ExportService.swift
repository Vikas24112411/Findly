import Foundation

/// Exports vault files as a ZIP archive without requiring a third-party library.
/// Uses ZIP STORE method (no compression — focus is on archiving, not size reduction).
///
/// Files are written directly to a temp file via FileHandle so the entire vault
/// is never held in memory simultaneously.
actor ExportService {

    // MARK: - Public interface

    /// Creates a ZIP archive of all locally available vault items and returns its URL.
    /// The caller is responsible for deleting the temp file when done.
    func exportVault(items: [Item], localStorage: LocalFileService) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Findly_Export_\(Int(Date().timeIntervalSince1970)).zip")

        // Create the file so FileHandle can open it for writing.
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? fileHandle.close() }

        var writer = ZipWriter(fileHandle: fileHandle)

        for item in items {
            guard let relativePath = item.localFilePath else { continue }
            let url = await localStorage.fileURL(relativePath: relativePath)
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else { continue }
            // Use the item's title as the filename in the archive, preserving the original extension.
            let ext = url.pathExtension.isEmpty ? item.fileType.fileExtension : url.pathExtension
            let safeName = sanitize(item.title) + "." + ext
            try writer.addFile(name: safeName, data: data)
        }

        try writer.finalize()
        return tempURL
    }

    // MARK: - Filename sanitization

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
            .prefix(60)
            .description
    }
}

// MARK: - Errors

enum ZipError: Error, LocalizedError {
    case tooManyFiles

    var errorDescription: String? {
        "ZIP export supports at most 65,535 files. Please export a smaller selection."
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
    private var currentOffset: UInt32 = 0

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
        let nameData = name.data(using: .utf8) ?? Data()
        let crc = crc32(data)
        let offset = currentOffset

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

        currentOffset += UInt32(header.count) + UInt32(nameData.count) + UInt32(data.count)
        entries.append(EntryMeta(name: nameData, dataSize: UInt32(data.count), crc32: crc, offset: offset))
    }

    // MARK: - Finalize (writes central directory + EOCD)

    mutating func finalize() throws {
        guard entries.count <= 65_535 else { throw ZipError.tooManyFiles }

        let centralDirStart = currentOffset
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
