import Foundation
import SwiftUI
import SwiftData
import UIKit
import AVFoundation
import PDFKit

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
            let fileSize = upload.fileSize ?? Int64(upload.data.count)
            let item = Item(
                title: title.isEmpty ? upload.suggestedTitle : title,
                fileType: upload.fileType,
                fileSize: fileSize,
                originalFileName: upload.fileName
            )
            item.itemDescription = itemDescription
            item.tags = Array(selectedTags)

            // 2. Generate thumbnail for images and PDFs (before storage write)
            if upload.fileType == .image, let uiImage = UIImage(data: upload.data) {
                item.thumbnailData = uiImage.jpegData(compressionQuality: 0.5)
            } else if upload.fileType == .pdf,
                      let doc = PDFDocument(data: upload.data),
                      let page = doc.page(at: 0) {
                let bounds = page.bounds(for: .mediaBox)
                let scale = 200.0 / bounds.width
                let renderer = UIGraphicsImageRenderer(
                    size: CGSize(width: 200, height: bounds.height * scale)
                )
                let image = renderer.image { ctx in page.draw(with: .mediaBox, to: ctx.cgContext) }
                item.thumbnailData = image.jpegData(compressionQuality: 0.5)
            }

            // 3. Save to local storage first (always)
            let relativePath: String
            if let sourceURL = upload.sourceURL {
                relativePath = try await localStorage.write(
                    from: sourceURL,
                    itemID: item.id,
                    fileExtension: upload.fileType.fileExtension
                )
            } else {
                relativePath = try await localStorage.write(
                    data: upload.data,
                    itemID: item.id,
                    fileExtension: upload.fileType.fileExtension
                )
            }
            item.localFilePath = relativePath

            // 3b. Generate video thumbnail from written file
            if upload.fileType == .video {
                let fileURL = await localStorage.fileURL(relativePath: relativePath)
                let asset = AVURLAsset(url: fileURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 400, height: 400)
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    item.thumbnailData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.5)
                }
            }

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
