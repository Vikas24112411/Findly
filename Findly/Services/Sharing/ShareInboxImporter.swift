import Foundation
import SwiftData

@MainActor
final class ShareInboxImporter {
    private var isImporting = false

    /// Uses a separate context so failed imports cannot roll back the user's edits.
    /// Stable item IDs make replay safe after a crash between commit and inbox cleanup.
    func importFiles(inbox: ShareInbox, container: ModelContainer, storage: LocalFileService,
                     authenticated: Bool) async throws -> Int {
        guard !isImporting else { return 0 }
        isImporting = true
        defer { isImporting = false }
        let packages = try await Task.detached { try inbox.packages() }.value
        var imported = 0
        var firstError: Error?
        for package in packages {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                let file = try await Task.detached { try inbox.read(package) }.value
                let id = file.id
                let existing = try context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.id == id }))
                if existing.isEmpty {
                    let source = package.appendingPathComponent("payload")
                    let size = try await Task.detached {
                        Int64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                    }.value
                    let ext = (file.originalName as NSString).pathExtension
                    // Preserve bytes and extension: HEIC, PNG and MOV must not be renamed JPG/MP4.
                    let storedExtension = ext.isEmpty ? "bin" : ext
                    let relativePath = "\(id.uuidString).\(storedExtension)"
                    if await storage.exists(relativePath: relativePath) {
                        // A prior attempt copied the payload but didn't commit its item.
                        try await storage.delete(relativePath: relativePath)
                    }
                    let path = try await storage.write(from: source, itemID: id, fileExtension: storedExtension)
                    let item = Item(id: id, title: file.title, fileType: FileType.detect(fileExtension: ext),
                                    fileSize: size, originalFileName: file.originalName)
                    item.itemDescription = file.notes
                    item.createdAt = file.createdAt
                    item.modifiedAt = file.createdAt
                    item.localFilePath = path
                    item.syncStatus = authenticated ? .pending : .localOnly
                    var tags = try context.fetch(FetchDescriptor<Tag>())
                    item.tags = tags.filter { file.tagIDs.contains($0.id) }
                    for name in file.newTagNames {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        let tag: Tag
                        if let match = tags.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                            tag = match
                        } else {
                            tag = Tag(name: trimmed)
                            context.insert(tag)
                            tags.append(tag)
                        }
                        if !item.tags.contains(where: { $0.id == tag.id }) { item.tags.append(tag) }
                    }
                    context.insert(item)
                    try context.save()
                    imported += 1
                    NotificationCenter.default.post(name: .itemSaved, object: nil)
                }
                try await Task.detached { try FileManager.default.removeItem(at: package) }.value
            } catch {
                context.rollback()
                if firstError == nil { firstError = error }
                // Leave this package intact for retry; other files can still be imported.
            }
        }
        if let firstError { throw firstError }
        return imported
    }
}
