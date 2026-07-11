import Foundation

/// Exports vault files as a ZIP archive without requiring a third-party library.
/// Uses ZIP STORE method (no compression — focus is on archiving, not size reduction).
actor ExportService {

    // MARK: - Public interface

    /// Creates a ZIP archive of all locally available vault items and returns its URL.
    /// The caller is responsible for deleting the temp file when done.
    func exportVault(items: [Item], localStorage: LocalFileService) async throws -> URL {
        var writer = ZipWriter()

        for item in items {
            guard let relativePath = item.localFilePath else { continue }
            let url = await localStorage.fileURL(relativePath: relativePath)
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else { continue }
            // Use the item's title as the filename in the archive, preserving the original extension
            let ext = url.pathExtension.isEmpty ? item.fileType.fileExtension : url.pathExtension
            let safeName = sanitize(item.title) + "." + ext
            writer.addFile(name: safeName, data: data)
        }

        let zipData = writer.finalize()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Findly_Export_\(Int(Date().timeIntervalSince1970)).zip")
        try zipData.write(to: tempURL)
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

// MARK: - Minimal ZIP writer (STORE, no compression)

private struct ZipWriter {

    private var buffer = Data()
    private var entries: [EntryMeta] = []

    private struct EntryMeta {
        let name: Data       // UTF-8 encoded filename
        let dataSize: UInt32
        let crc32: UInt32
        let offset: UInt32   // byte offset of local file header in buffer
    }

    // MARK: - Add file

    mutating func addFile(name: String, data: Data) {
        let nameData = name.data(using: .utf8) ?? Data()
        let crc = crc32(data)
        let offset = UInt32(buffer.count)

        // Local file header
        append(uint32: 0x04034b50)            // PK\x03\x04
        append(uint16: 20)                     // version needed
        append(uint16: 0x0800)                 // UTF-8 flag (bit 11)
        append(uint16: 0)                      // compression: STORE
        append(uint16: dosTime())
        append(uint16: dosDate())
        append(uint32: crc)
        append(uint32: UInt32(data.count))     // compressed size = uncompressed (STORE)
        append(uint32: UInt32(data.count))
        append(uint16: UInt16(nameData.count))
        append(uint16: 0)                      // extra field length
        buffer.append(nameData)
        buffer.append(data)

        entries.append(EntryMeta(name: nameData, dataSize: UInt32(data.count), crc32: crc, offset: offset))
    }

    // MARK: - Finalize

    mutating func finalize() -> Data {
        let centralDirStart = UInt32(buffer.count)
        var centralDirSize: UInt32 = 0

        for entry in entries {
            append(uint32: 0x02014b50)         // central directory signature
            append(uint16: 20)                  // version made by
            append(uint16: 20)                  // version needed
            append(uint16: 0x0800)              // UTF-8 flag
            append(uint16: 0)                   // compression: STORE
            append(uint16: dosTime())
            append(uint16: dosDate())
            append(uint32: entry.crc32)
            append(uint32: entry.dataSize)
            append(uint32: entry.dataSize)
            append(uint16: UInt16(entry.name.count))
            append(uint16: 0)                   // extra length
            append(uint16: 0)                   // comment length
            append(uint16: 0)                   // disk number start
            append(uint16: 0)                   // internal attrs
            append(uint32: 0)                   // external attrs
            append(uint32: entry.offset)
            buffer.append(entry.name)
            centralDirSize += 46 + UInt32(entry.name.count)
        }

        // End of central directory record
        append(uint32: 0x06054b50)
        append(uint16: 0)                       // disk number
        append(uint16: 0)                       // disk with central dir
        append(uint16: UInt16(entries.count))
        append(uint16: UInt16(entries.count))
        append(uint32: centralDirSize)
        append(uint32: centralDirStart)
        append(uint16: 0)                       // comment length

        return buffer
    }

    // MARK: - Helpers

    private mutating func append(uint16 value: UInt16) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { buffer.append(contentsOf: $0) }
    }

    private mutating func append(uint32 value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { buffer.append(contentsOf: $0) }
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

    // Standard CRC-32 (ISO 3309 / ITU-T V.42) — same polynomial used by zlib
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
