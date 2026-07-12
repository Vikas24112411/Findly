import Foundation
import SwiftUI
import SwiftData
import UIKit

@Observable
@MainActor
final class ItemFormViewModel {

    // MARK: - State

    var title: String = ""
    var itemDescription: String = ""
    var selectedTags: Set<Tag> = []
    var showNotes: Bool = false
    var isSaving: Bool = false
    var saveError: Error? = nil
    var savedItem: Item? = nil

    // MARK: - Tag search

    var tagSearchText: String = ""

    // MARK: - Input (set by caller)

    var pendingUpload: PendingUpload?

    // MARK: - Save

    func save(
        context: ModelContext,
        sync: SyncService,
        localStorage: LocalFileService,
        isAuthenticated: Bool
    ) async {
        guard let upload = pendingUpload else { return }
        isSaving = true
        saveError = nil

        do {
            // 1. Create Item
            let item = Item(
                title: title.isEmpty ? upload.suggestedTitle : title,
                fileType: upload.fileType,
                fileSize: Int64(upload.data.count),
                originalFileName: upload.fileName
            )
            item.itemDescription = itemDescription
            item.tags = Array(selectedTags)

            // 2. Generate thumbnail if image
            if upload.fileType == .image, let uiImage = UIImage(data: upload.data) {
                item.thumbnailData = uiImage.jpegData(compressionQuality: 0.5)
            }

            // 3. Save to local storage first (always)
            let relativePath = try await localStorage.write(
                data: upload.data,
                itemID: item.id,
                fileExtension: upload.fileType.fileExtension
            )
            item.localFilePath = relativePath

            // 4. Set sync status based on Drive connection
            item.syncStatus = isAuthenticated ? .pending : .localOnly

            // 5. Persist to SwiftData
            context.insert(item)
            try context.save()
            savedItem = item
            isSaving = false
            HapticFeedback.success()

            // 6. Trigger Drive upload in the background (don't block success screen)
            if isAuthenticated {
                Task { await sync.syncPendingItems() }
            }
        } catch {
            saveError = error
            isSaving = false
        }
    }

    // MARK: - Tag helpers

    func filteredTags(from allTags: [Tag]) -> [Tag] {
        if tagSearchText.isEmpty { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(tagSearchText) }
    }

    func toggleTag(_ tag: Tag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}
