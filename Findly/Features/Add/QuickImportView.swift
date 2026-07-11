import SwiftUI
import SwiftData

/// Bulk-import screen: shows a list of files from the Files app and saves them all at once.
struct QuickImportView: View {

    let urls: [URL]
    var onDone: () -> Void

    @Environment(AppContainer.self) private var appContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var importState: ImportState = .ready
    @State private var importedCount = 0

    enum ImportState { case ready, importing, done, failed }

    private var fileInfos: [(url: URL, title: String, fileType: FileType)] {
        urls.map { url in
            let ext = url.pathExtension
            let ft = FileType.detect(fileExtension: ext)
            let title = url.deletingPathExtension().lastPathComponent
            return (url, title, ft)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch importState {
                case .ready:
                    fileList
                case .importing:
                    importingView
                case .done:
                    doneView
                case .failed:
                    Text("Import failed. Please try again.")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Import \(urls.count) File\(urls.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(importState == .importing)
                }
                if importState == .ready {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import All") { startImport() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - File list

    private var fileList: some View {
        List(fileInfos, id: \.url) { info in
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: info.fileType.sfSymbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(info.fileType.tintColor)
                    .frame(width: 36, height: 36)
                    .background(info.fileType.tintColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(AppTheme.Typography.headline)
                        .lineLimit(1)
                    Text(info.fileType.displayName)
                        .font(AppTheme.Typography.caption1)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Importing

    private var importingView: some View {
        VStack(spacing: AppTheme.Spacing.xLarge) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Importing \(importedCount) of \(urls.count)…")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: AppTheme.Spacing.xLarge) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("\(importedCount) file\(importedCount == 1 ? "" : "s") imported")
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.label)
            Button("Done") {
                HapticFeedback.success()
                onDone()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Import logic

    private func startImport() {
        importState = .importing
        Task {
            var count = 0
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { continue }

                let ext = url.pathExtension
                let ft = FileType.detect(fileExtension: ext)
                let title = url.deletingPathExtension().lastPathComponent
                let item = Item(
                    title: title.isEmpty ? "Untitled" : title,
                    fileType: ft,
                    fileSize: Int64(data.count),
                    originalFileName: url.lastPathComponent
                )

                // Generate thumbnail for images
                if ft == .image, let ui = UIImage(data: data) {
                    item.thumbnailData = ui.jpegData(compressionQuality: 0.5)
                }

                if let relativePath = try? await appContainer.localStorage.write(
                    data: data,
                    itemID: item.id,
                    fileExtension: ft.fileExtension
                ) {
                    item.localFilePath = relativePath
                }
                item.syncStatus = appContainer.auth.isAuthenticated ? .pending : .localOnly

                await MainActor.run {
                    modelContext.insert(item)
                    count += 1
                    importedCount = count
                }
            }

            await MainActor.run {
                try? modelContext.save()
                if appContainer.auth.isAuthenticated {
                    Task { await appContainer.sync.syncPendingItems() }
                }
                importState = .done
            }
        }
    }
}
