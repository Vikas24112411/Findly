import SwiftUI
import SwiftData
import QuickLook

struct ItemDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.dismiss) private var dismiss

    let item: Item

    @State private var quickLookURL: URL?
    @State private var showQuickLook = false
    @State private var isDownloading = false
    @State private var downloadError: Error?
    @State private var showDeleteConfirm = false
    @State private var showTagPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xLarge) {
                thumbnailHeader
                metaSection
                tagsSection
                actionsSection
            }
            .padding(.horizontal, AppTheme.Spacing.base)
            .padding(.vertical, AppTheme.Spacing.large)
        }
        .background(AppTheme.Colors.groupedBG)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    item.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(item.isFavorite ? .pink : AppTheme.Colors.secondaryLabel)
                }
            }
        }
        .quickLookPreview($quickLookURL)
        .sheet(isPresented: $showTagPicker) {
            TagPickerSheet(item: item) { tag in
                addTag(tag)
            }
        }
        .alert("Delete Item?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteItem() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the file from your vault and Google Drive.")
        }
        .onAppear {
            item.markOpened()
            try? modelContext.save()
        }
    }

    // MARK: - Thumbnail

    private var thumbnailHeader: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.xLarge, style: .continuous)
                .fill(item.fileType.tintColor.opacity(0.10))
                .frame(maxWidth: .infinity)
                .frame(height: 220)

            if let data = item.thumbnailData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xLarge, style: .continuous))
            } else {
                VStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: item.fileType.sfSymbol)
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(item.fileType.tintColor)
                    Text(item.fileType.displayName)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(item.fileType.tintColor.opacity(0.7))
                }
            }
        }
        .onTapGesture { openFile() }
    }

    // MARK: - Meta

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text(item.title)
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.label)

            if !item.itemDescription.isEmpty {
                Text(item.itemDescription)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }

            Divider()

            metaRow(label: "Size",     value: item.fileSize.fileSizeString)
            metaRow(label: "Added",    value: item.createdAt.fullDateTimeString)
            metaRow(label: "Modified", value: item.modifiedAt.fullDateTimeString)
            if let opened = item.lastOpenedAt {
                metaRow(label: "Opened", value: opened.relativeString)
            }
            metaRow(label: "Views", value: "\(item.viewCount)")
            HStack {
                Text("Sync")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                Spacer()
                HStack(spacing: 4) {
                    SyncStatusBadge(status: item.syncStatus)
                    Text(item.syncStatus.displayLabel)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(item.syncStatus.tintColor)
                }
            }
        }
        .padding(AppTheme.Spacing.base)
        .background(AppTheme.Colors.secondaryBG)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
            Spacer()
            Text(value)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.label)
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                Text("Tags")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.label)
                Spacer()
                Button { showTagPicker = true } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            if item.tags.isEmpty {
                Text("No tags — tap + to add one")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
            } else {
                FlowLayout(spacing: AppTheme.Spacing.small) {
                    ForEach(item.tags.sorted { $0.name < $1.name }) { tag in
                        TagChipView(tag: tag)
                            .overlay(alignment: .topTrailing) {
                                Button { removeTag(tag) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                                        .background(AppTheme.Colors.secondaryBG.opacity(0.8))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                            }
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.base)
        .background(AppTheme.Colors.secondaryBG)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
    }

    private func addTag(_ tag: Tag) {
        guard !item.tags.contains(where: { $0.id == tag.id }) else { return }
        item.tags.append(tag)
        try? modelContext.save()
    }

    private func removeTag(_ tag: Tag) {
        item.tags.removeAll { $0.id == tag.id }
        try? modelContext.save()
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            // Drive recovery: local file missing but Drive copy exists
            if !item.localFileAvailable && item.isUploaded {
                Button {
                    Task { try? await appContainer.sync.recoverFromDrive(item: item) }
                } label: {
                    Label("Download from Drive", systemImage: "icloud.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.medium)
                        .background(AppTheme.Colors.secondaryBG)
                        .foregroundStyle(AppTheme.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                        .font(AppTheme.Typography.headline)
                }
            }

            // Drive backup: file is local-only; Drive available or not
            if item.syncStatus == .localOnly {
                if appContainer.auth.isAuthenticated {
                    Button {
                        Task {
                            appContainer.sync.promoteLocalOnlyItems()
                            await appContainer.sync.syncPendingItems()
                        }
                    } label: {
                        Label("Back Up to Google Drive", systemImage: "icloud.and.arrow.up.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.medium)
                            .background(AppTheme.Colors.secondaryBG)
                            .foregroundStyle(AppTheme.Colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                            .font(AppTheme.Typography.headline)
                    }
                } else {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Image(systemName: "iphone")
                            .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        Text("Connect Google Drive in Settings to back up this file.")
                            .font(AppTheme.Typography.caption1)
                            .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.medium)
                }
            }

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.medium)
                    .background(Color.red.opacity(0.08))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                    .font(AppTheme.Typography.headline)
            }
        }
    }

    // MARK: - Open file

    private func openFile() {
        guard let relativePath = item.localFilePath else { return }
        Task {
            let url = await appContainer.localStorage.fileURL(relativePath: relativePath)
            quickLookURL = url
        }
    }

    // MARK: - Delete

    private func deleteItem() {
        if let path = item.localFilePath {
            Task { try? await appContainer.localStorage.delete(relativePath: path) }
        }
        if let driveID = item.googleDriveFileID {
            Task { try? await appContainer.drive.deleteFile(driveFileID: driveID) }
        }
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Tag picker sheet

struct TagPickerSheet: View {
    let item: Item
    var onAdd: (Tag) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var allTags: [Tag] = []
    @State private var searchText = ""

    private var availableTags: [Tag] {
        let unassigned = allTags.filter { tag in
            !item.tags.contains(where: { $0.id == tag.id })
        }
        if searchText.isEmpty { return unassigned }
        return unassigned.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableTags.isEmpty {
                    Text(allTags.isEmpty ? "No tags created yet." : "All tags are already assigned.")
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(availableTags) { tag in
                        Button {
                            onAdd(tag)
                            dismiss()
                        } label: {
                            HStack(spacing: AppTheme.Spacing.medium) {
                                Image(systemName: tag.sfSymbol)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(hex: tag.colorHex))
                                    .frame(width: 22, height: 22)
                                    .background(Color(hex: tag.colorHex).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(tag.name)
                                    .foregroundStyle(AppTheme.Colors.label)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search tags...")
            .navigationTitle("Add Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                allTags = ((try? modelContext.fetch(FetchDescriptor<Tag>(
                    sortBy: [SortDescriptor(\.name)]
                ))) ?? [])
            }
        }
    }
}

// MARK: - Simple flow layout for tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
