import Foundation
import SwiftData

// MARK: - Import errors

enum ImportError: Error, LocalizedError {
    case notAFindlyVault
    case unsupportedVersion(Int)
    case corruptManifest

    var errorDescription: String? {
        switch self {
        case .notAFindlyVault:
            return "The selected file is not a valid Findly vault export."
        case .unsupportedVersion(let v):
            return "This vault was exported with a newer version of Findly (format v\(v)) and cannot be imported."
        case .corruptManifest:
            return "The vault manifest is missing or corrupt. The file may be damaged."
        }
    }
}

// MARK: - ImportService

/// Restores a vault from a ZIP archive previously created by `ExportService`.
///
/// **Destructive operation:** all existing items, tags, and search history are deleted
/// before the imported data is written. The caller must obtain explicit user confirmation
/// before invoking `importVault`.
@MainActor
final class ImportService {

    func importVault(
        from zipURL: URL,
        localStorage: LocalFileService,
        context: ModelContext,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws {
        // 1. Load ZIP on a background thread so the main actor stays responsive.
        //    Data(contentsOf:) is synchronous and can block for several seconds on large vaults.
        let zipData = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: zipURL)
        }.value
        let reader = ZipReader(zipData: zipData)
        let entries = try reader.entries()

        // 2. Locate and decode manifest.
        guard let manifestEntry = entries.first(where: { $0.name == "manifest.json" }) else {
            throw ImportError.notAFindlyVault
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(ExportManifest.self, from: manifestEntry.data) else {
            throw ImportError.corruptManifest
        }
        guard manifest.version == 1 else {
            throw ImportError.unsupportedVersion(manifest.version)
        }

        // 3. Write primary files to localStorage; keep thumbnails in memory.
        //    Files are written BEFORE the wipe so a failure here leaves existing SwiftData
        //    records intact (no context.save() has been called yet).
        //    Thumbnails are kept in memory so SwiftData's @Attribute(.externalStorage)
        //    remains the sole on-disk copy — no orphan sidecar files created.
        let fileEntries = entries.filter { $0.name != "manifest.json" }
        let fileTotal = max(1, fileEntries.count)
        var thumbnailsByName: [String: Data] = [:]
        for (i, entry) in fileEntries.enumerated() {
            if entry.name.hasSuffix("_thumb.jpg") {
                thumbnailsByName[entry.name] = entry.data
                // Yield so the main actor can update the UI between thumbnail entries
                // (thumbnail assignments have no natural suspension point).
                await Task.yield()
            } else {
                try await localStorage.writeFile(named: entry.name, data: entry.data)
            }
            if let onProgress { await onProgress(Double(i + 1) / Double(fileTotal) * 0.5) }
        }

        // 4–9. All SwiftData mutations run on a SIBLING context, not the main context.
        //
        //    Root cause of the crash: the caller passes the @Environment(\.modelContext) main
        //    context. Calling context.delete() on it immediately triggers @Observable change
        //    notifications for `isDeleted`. The next `await` yields the main actor, SwiftUI
        //    re-renders background views that still hold Item references from @Query results,
        //    and those views call item.fileType — which is still an unresolved attribute fault
        //    (SwiftData lazy-loads every @Model property). SwiftData cannot fire a fault on a
        //    staged-but-unsaved deleted object → "backing data was detached" fatal crash.
        //
        //    Using a sibling ModelContext means the main context (and all @Query observers)
        //    never sees any intermediate state. It only receives a single persistent-store
        //    merge notification at each importContext.save(), by which point the objects are
        //    either fully deleted or fully committed — never in a half-deleted/faulted limbo.
        //
        //    Two saves are required: the first commits only the deletes so the store is clean
        //    before we insert new items. This avoids an @Attribute(.unique) upsert-merge where
        //    SwiftData would merge new values into the existing (staged-for-deletion) object
        //    and detach the newly-created object's backing — the same crash, different path.
        let importContext = ModelContext(context.container)

        // 4. Delete existing data on the import context.
        //    Note: context.delete(model:) is a SQL batch delete that fails on the Item↔Tag
        //    M2M relationship ("Constraint trigger violation: Batch delete failed due to
        //    mandatory MTM nullify inverse on item/tags"). Fetching + deleting individually
        //    lets SwiftData properly nullify the join table entries first.
        let existingItems = try importContext.fetch(FetchDescriptor<Item>())
        existingItems.forEach { importContext.delete($0) }
        let existingTags = try importContext.fetch(FetchDescriptor<Tag>())
        existingTags.forEach { importContext.delete($0) }
        let existingHistory = try importContext.fetch(FetchDescriptor<SearchHistoryEntry>())
        existingHistory.forEach { importContext.delete($0) }
        // Commit deletes before inserting so there are no @Attribute(.unique) conflicts.
        // Files are already written (step 3), so a failure here still leaves the ZIP
        // available for a clean re-import.
        try importContext.save()

        // 5. Recreate tags — pass 1: create all Tag objects without parent relationships.
        var tagByID: [UUID: Tag] = [:]
        for exportTag in manifest.tags {
            let tag = Tag(name: exportTag.name, colorHex: exportTag.colorHex, sfSymbol: exportTag.sfSymbol)
            tag.id = exportTag.id
            tag.createdAt = exportTag.createdAt
            importContext.insert(tag)
            tagByID[exportTag.id] = tag
        }

        // 6. Recreate tag parent relationships — pass 2 (avoids forward-reference issues).
        for exportTag in manifest.tags {
            guard let tag = tagByID[exportTag.id] else { continue }
            tag.parents = exportTag.parentIDs.compactMap { tagByID[$0] }
        }

        // 7. Recreate search history.
        for entry in manifest.searchHistory {
            let historyEntry = SearchHistoryEntry(query: entry.query)
            historyEntry.id = entry.id
            historyEntry.timestamp = entry.timestamp
            historyEntry.useCount = entry.useCount
            importContext.insert(historyEntry)
        }

        // 8. Recreate items. (progress 0.5 → 1.0)
        let itemTotal = max(1, manifest.items.count)
        for (itemIndex, exportItem) in manifest.items.enumerated() {
            let item = Item(
                title: exportItem.title,
                fileType: exportItem.fileType,
                fileSize: exportItem.fileSize,
                originalFileName: exportItem.originalFileName
            )
            item.id = exportItem.id
            item.itemDescription = exportItem.itemDescription
            item.localFilePath = exportItem.localFilePath
            item.googleDriveFileID = exportItem.googleDriveFileID
            // Reset to localOnly — Drive IDs are preserved but re-sync should be triggered manually.
            item.syncStatus = .localOnly
            item.createdAt = exportItem.createdAt
            item.modifiedAt = exportItem.modifiedAt
            item.lastOpenedAt = exportItem.lastOpenedAt
            item.viewCount = exportItem.viewCount
            item.isFavorite = exportItem.isFavorite
            item.isPinned = exportItem.isPinned
            item.tags = exportItem.tagIDs.compactMap { tagByID[$0] }

            // Assign thumbnail directly from in-memory ZIP data — no disk round-trip needed.
            let thumbName = "\(exportItem.id.uuidString)_thumb.jpg"
            item.thumbnailData = thumbnailsByName[thumbName]

            importContext.insert(item)
            if let onProgress { await onProgress(0.5 + Double(itemIndex + 1) / Double(itemTotal) * 0.5) }
        }

        // 9. Commit all new inserts.
        try importContext.save()

        // 10. Cleanup orphan files: remove anything in baseDirectory not referenced by the new vault.
        //     Best-effort — orphans are storage waste, not data loss.
        let newFilePaths = Set(manifest.items.compactMap { $0.localFilePath })
        await localStorage.deleteFilesExcept(newFilePaths)
    }
}

// MARK: - ZIP reader (STORE format only)
//
// Reads the local-file-header stream written by ZipWriter.
// Compression method must be STORE (0); no decompression is performed.

private struct ZipReader {

    let zipData: Data

    enum ZipReadError: Error, LocalizedError {
        case invalidData
        var errorDescription: String? { "The ZIP archive is corrupt or truncated." }
    }

    func entries() throws -> [ZipEntry] {
        var result: [ZipEntry] = []
        var offset = 0

        while offset + 4 <= zipData.count {
            let sig = readUInt32(at: offset)

            // Stop at central directory or EOCD.
            if sig == 0x02014b50 || sig == 0x06054b50 { break }

            // Expect a local file header.
            guard sig == 0x04034b50 else {
                offset += 1
                continue
            }

            guard offset + 30 <= zipData.count else { throw ZipReadError.invalidData }

            let compressedSize = Int(readUInt32(at: offset + 18))
            let nameLen        = Int(readUInt16(at: offset + 26))
            let extraLen       = Int(readUInt16(at: offset + 28))

            let nameStart = offset + 30
            let dataStart = nameStart + nameLen + extraLen

            guard dataStart + compressedSize <= zipData.count else { throw ZipReadError.invalidData }

            let nameData = zipData[nameStart ..< (nameStart + nameLen)]
            guard let name = String(data: nameData, encoding: .utf8) else {
                offset = dataStart + compressedSize
                continue
            }

            let fileData = Data(zipData[dataStart ..< (dataStart + compressedSize)])
            result.append(ZipEntry(name: name, data: fileData))

            offset = dataStart + compressedSize
        }

        return result
    }

    // MARK: - Little-endian reads

    private func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= zipData.count else { return 0 }
        return zipData[offset ..< offset + 2].withUnsafeBytes {
            $0.loadUnaligned(as: UInt16.self).littleEndian
        }
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= zipData.count else { return 0 }
        return zipData[offset ..< offset + 4].withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).littleEndian
        }
    }
}

private struct ZipEntry {
    let name: String
    let data: Data
}
