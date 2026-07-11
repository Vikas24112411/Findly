import Foundation
import SwiftUI
import SwiftData
import UIKit

@Observable
@MainActor
final class UploadFlowViewModel {

    // MARK: - Step enum

    enum Step: Int, CaseIterable, Comparable {
        case preview, title, tags, description, saving

        static func < (lhs: Step, rhs: Step) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - State

    var currentStep: Step = .preview
    var title: String = ""
    var itemDescription: String = ""
    var selectedTags: Set<Tag> = []
    var isSaving: Bool = false
    var saveError: Error? = nil
    var savedItem: Item? = nil

    // MARK: - Tag search

    var tagSearchText: String = ""

    // MARK: - Input (set by caller)

    var pendingUpload: PendingUpload?

    // MARK: - Navigation

    func advance() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(AppTheme.Animation.fast) {
            currentStep = next
        }
    }

    func goBack() {
        guard let prev = Step(rawValue: currentStep.rawValue - 1) else { return }
        withAnimation(AppTheme.Animation.fast) {
            currentStep = prev
        }
    }

    // MARK: - Save

    func save(
        context: ModelContext,
        sync: SyncService,
        localStorage: LocalFileService,
        isAuthenticated: Bool
    ) async {
        guard let upload = pendingUpload else { return }
        currentStep = .saving
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
