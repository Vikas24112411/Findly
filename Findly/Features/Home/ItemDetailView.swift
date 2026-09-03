import SwiftUI
import SwiftData
import QuickLook

@Observable
@MainActor
final class FileViewerCoordinator {
    var selectedItem: Item?

    func open(_ item: Item) {
        selectedItem = item
    }

    func close() {
        selectedItem = nil
    }
}

enum FileResolutionStrategy: Equatable {
    case useLocalFile
    case recoverFromDrive
    case unavailable

    static func choose(hasLocalFile: Bool, hasRemoteFile: Bool) -> Self {
        if hasLocalFile { return .useLocalFile }
        if hasRemoteFile { return .recoverFromDrive }
        return .unavailable
    }
}

struct FileOpenSession {
    private(set) var hasRecordedOpen = false

    @discardableResult
    mutating func recordOpen(for item: Item) -> Bool {
        guard !hasRecordedOpen else { return false }
        hasRecordedOpen = true
        item.markOpened()
        return true
    }
}

struct FileViewerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @Environment(FileViewerCoordinator.self) private var viewerCoordinator

    let item: Item

    @State private var previewURL: URL?
    @State private var isResolving = false
    @State private var resolutionError: String?
    @State private var showInspector = false
    @State private var inspectorDetent: PresentationDetent = .fraction(0.45)
    @State private var openSession = FileOpenSession()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let previewURL {
                QuickLookController(url: previewURL)
                    .ignoresSafeArea()
            } else if isResolving {
                loadingState
            } else if let resolutionError {
                errorState(message: resolutionError)
            }

            viewerChrome
        }
        .statusBarHidden()
        .task(id: item.id) { await resolveFile() }
        .sheet(isPresented: $showInspector) {
            MetadataInspectorView(
                item: item,
                resolvedURL: previewURL,
                selectedDetent: $inspectorDetent,
                onRetry: {
                    showInspector = false
                    Task { await resolveFile() }
                },
                onDelete: {
                    showInspector = false
                    viewerCoordinator.close()
                }
            )
            .presentationDetents(
                [.fraction(0.45), .fraction(0.60)],
                selection: $inspectorDetent
            )
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(AppTheme.Radius.xLarge)
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.60)))
            .presentationContentInteraction(.scrolls)
        }
    }

    private var viewerChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.medium) {
                chromeButton(symbol: "xmark", label: "Close file") {
                    viewerCoordinator.close()
                }

                Text(item.title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                chromeButton(symbol: "info.circle", label: "Show file information") {
                    openInspector()
                }
            }
            .padding(.horizontal, AppTheme.Spacing.base)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(.ultraThinMaterial)

            Spacer()

            Button {
                openInspector()
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "chevron.up")
                        .font(.caption.bold())
                    Capsule()
                        .frame(width: 38, height: 5)
                }
                .foregroundStyle(.white)
                .frame(width: 96, height: 48)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show file information")
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        if value.translation.height <= -30 {
                            openInspector()
                            HapticFeedback.light()
                        }
                    }
            )
            .padding(.bottom, AppTheme.Spacing.medium)
        }
    }

    private func chromeButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var loadingState: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            ProgressView()
                .tint(.white)
                .controlSize(.large)
            Text(item.googleDriveFileID == nil ? "Opening file…" : "Downloading from Google Drive…")
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.75))
            VStack(spacing: AppTheme.Spacing.small) {
                Text("Unable to Open File")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(.white)
                Text(message)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: AppTheme.Spacing.medium) {
                Button("File Info") { openInspector() }
                    .buttonStyle(.bordered)
                Button("Retry") { Task { await resolveFile() } }
                    .buttonStyle(.borderedProminent)
            }
            .tint(AppTheme.Colors.accent)
        }
        .padding(AppTheme.Spacing.xLarge)
    }

    @MainActor
    private func resolveFile() async {
        guard !isResolving else { return }
        isResolving = true
        resolutionError = nil
        defer { isResolving = false }

        let hasLocalFile: Bool
        if let relativePath = item.localFilePath {
            hasLocalFile = await appContainer.localStorage.exists(relativePath: relativePath)
        } else {
            hasLocalFile = false
        }

        switch FileResolutionStrategy.choose(
            hasLocalFile: hasLocalFile,
            hasRemoteFile: item.googleDriveFileID != nil
        ) {
        case .useLocalFile:
            guard let relativePath = item.localFilePath else { return }
            previewURL = await appContainer.localStorage.fileURL(relativePath: relativePath)
            recordSuccessfulOpen()

        case .recoverFromDrive:
            do {
                try await appContainer.sync.recoverFromDrive(item: item)
                guard let relativePath = item.localFilePath,
                      await appContainer.localStorage.exists(relativePath: relativePath) else {
                    throw SyncError.noLocalFile
                }
                previewURL = await appContainer.localStorage.fileURL(relativePath: relativePath)
                recordSuccessfulOpen()
            } catch {
                resolutionError = error.localizedDescription
            }

        case .unavailable:
            resolutionError = "The local file is missing and no Google Drive copy is available."
        }
    }

    private func recordSuccessfulOpen() {
        guard openSession.recordOpen(for: item) else { return }
        try? modelContext.save()
    }

    private func openInspector() {
        inspectorDetent = .fraction(0.45)
        showInspector = true
    }
}

private struct QuickLookController: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct MetadataInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let item: Item
    let resolvedURL: URL?
    @Binding var selectedDetent: PresentationDetent
    var onRetry: () -> Void
    var onDelete: () -> Void

    @State private var titleText: String
    @State private var descriptionText: String
    @State private var descriptionBeforeEditing: String
    @State private var isAddingDescription = false
    @State private var isDetailsExpanded = false
    @State private var showTagPicker = false
    @State private var shareURL: URL?
    @State private var showDeleteConfirm = false
    @State private var deleteError: Error?
    @State private var isDeleting = false
    @FocusState private var focusedField: Field?

    private enum Field { case title, description }

    init(
        item: Item,
        resolvedURL: URL?,
        selectedDetent: Binding<PresentationDetent>,
        onRetry: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.resolvedURL = resolvedURL
        _selectedDetent = selectedDetent
        self.onRetry = onRetry
        self.onDelete = onDelete
        _titleText = State(initialValue: item.title)
        _descriptionText = State(initialValue: item.itemDescription)
        _descriptionBeforeEditing = State(initialValue: item.itemDescription)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.large) {
                    header
                    quickActions
                    descriptionSection
                    tagsSection
                    detailsSection
                    syncSection
                }
                .padding(.horizontal, AppTheme.Spacing.base)
                .padding(.bottom, AppTheme.Spacing.xLarge)
            }
            .background(AppTheme.Colors.groupedBG)
            .navigationTitle("File Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .description {
                        Button("Cancel") { cancelDescriptionEditing() }
                    }
                    Spacer()
                    Button("Done") { finishEditing() }
                }
            }
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .title && newValue != .title { commitTitle() }
            if oldValue == .description && newValue != .description {
                finishDescriptionEditing(clearFocus: false)
            }
            if newValue == .description {
                descriptionBeforeEditing = item.itemDescription
                withAnimation(AppTheme.Animation.snappy) {
                    isAddingDescription = true
                    isDetailsExpanded = false
                    selectedDetent = .fraction(0.60)
                }
            }
        }
        .onDisappear {
            commitTitle()
            commitDescription()
        }
        .sheet(isPresented: $showTagPicker) {
            TagPickerSheet(item: item, onToggle: toggleTag)
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
        .alert("Delete File?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteItem() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the file from your vault and Google Drive.")
        }
        .alert("Delete Failed", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError?.localizedDescription ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(item.fileType.tintColor.opacity(0.12))
                Image(systemName: item.fileType.sfSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.fileType.tintColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                TextField("File name", text: $titleText)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.label)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { commitTitle() }
                    .accessibilityLabel("File name")
                HStack(spacing: 6) {
                    Text("\(item.fileType.displayName) · \(item.fileSize.fileSizeString)")
                        .lineLimit(1)
                    Spacer(minLength: AppTheme.Spacing.small)
                    HStack(spacing: 4) {
                        SyncStatusBadge(status: item.syncStatus)
                        Text(item.syncStatus.displayLabel)
                            .foregroundStyle(item.syncStatus.tintColor)
                            .lineLimit(1)
                    }
                }
                .font(AppTheme.Typography.caption1)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppTheme.Spacing.small)
    }

    private var quickActions: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            inspectorAction(
                title: "Favorite",
                symbol: item.isFavorite ? "heart.fill" : "heart",
                tint: AppTheme.Colors.favoriteTint,
                isSelected: item.isFavorite,
                accessibilityValue: item.isFavorite ? "On" : "Off"
            ) {
                item.isFavorite.toggle()
                saveWithHaptic()
            }
            inspectorAction(
                title: "Pin",
                symbol: item.isPinned ? "pin.fill" : "pin",
                tint: AppTheme.Colors.pinnedTint,
                isSelected: item.isPinned,
                accessibilityValue: item.isPinned ? "On" : "Off"
            ) {
                item.isPinned.toggle()
                saveWithHaptic()
            }
            inspectorAction(
                title: "Share",
                symbol: "square.and.arrow.up",
                tint: AppTheme.Colors.accent
            ) {
                shareURL = resolvedURL
            }
            .disabled(resolvedURL == nil)
            inspectorAction(
                title: "Delete",
                symbol: "trash",
                tint: .red,
                isLoading: isDeleting
            ) {
                showDeleteConfirm = true
            }
            .disabled(isDeleting)
        }
    }

    private func inspectorAction(
        title: String,
        symbol: String,
        tint: Color,
        isSelected: Bool = false,
        accessibilityValue: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xSmall) {
                ZStack {
                    Circle()
                        .fill(isSelected ? tint : tint.opacity(0.12))
                    if isLoading {
                        ProgressView()
                            .tint(tint)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : tint)
                    }
                }
                .frame(width: 44, height: 44)
                Text(title)
                    .font(AppTheme.Typography.caption1.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.label)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue ?? "")
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if hasDescription || isAddingDescription || focusedField == .description {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label("Description", systemImage: "text.alignleft")
                    .font(AppTheme.Typography.caption1.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)

                TextField("Add a description", text: $descriptionText, axis: .vertical)
                    .lineLimit(1...4)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.label)
                    .focused($focusedField, equals: .description)
                    .accessibilityLabel("File description")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.Colors.secondaryBG)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        } else {
            Button(action: beginAddingDescription) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.Colors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    Text("Add a description")
                        .font(AppTheme.Typography.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.label)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(AppTheme.Colors.accent)
                }
                .padding(AppTheme.Spacing.medium)
                .background(AppTheme.Colors.secondaryBG)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a description")
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text("Tags")
                .font(AppTheme.Typography.caption1.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.secondaryLabel)

            FlowLayout(
                spacing: AppTheme.Spacing.small,
                verticalSpacing: AppTheme.Spacing.xxSmall
            ) {
                ForEach(item.tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { tag in
                    removableTagChip(tag)
                }
                addTagChip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailsSection: some View {
        VStack(spacing: 0) {
            Button(action: toggleDetails) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.Colors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("More Details")
                            .font(AppTheme.Typography.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.label)
                        Text("Added \(item.createdAt.relativeString) · \(viewCountText)")
                            .font(AppTheme.Typography.caption2)
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        .rotationEffect(.degrees(isDetailsExpanded ? 180 : 0))
                }
                .padding(AppTheme.Spacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDetailsExpanded ? "Collapse file details" : "Expand file details")
            .accessibilityValue(isDetailsExpanded ? "Expanded" : "Collapsed")

            if isDetailsExpanded {
                VStack(spacing: AppTheme.Spacing.medium) {
                    activityRow(
                        symbol: "doc",
                        title: "Original File",
                        primary: item.originalFileName.isEmpty ? "Not available" : item.originalFileName
                    )
                    activityRow(
                        symbol: "calendar.badge.plus",
                        title: "Added",
                        primary: item.createdAt.relativeString,
                        secondary: item.createdAt.fullDateTimeString
                    )
                    activityRow(
                        symbol: "pencil",
                        title: "Modified",
                        primary: item.modifiedAt.relativeString,
                        secondary: item.modifiedAt.fullDateTimeString
                    )
                    if let opened = item.lastOpenedAt {
                        activityRow(
                            symbol: "clock.arrow.circlepath",
                            title: "Last Opened",
                            primary: opened.relativeString,
                            secondary: opened.fullDateTimeString
                        )
                    }
                    activityRow(symbol: "eye", title: "Views", primary: viewCountText)
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.bottom, AppTheme.Spacing.medium)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppTheme.Colors.secondaryBG)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
    }

    @ViewBuilder
    private var syncSection: some View {
        if resolvedURL == nil, item.googleDriveFileID != nil {
            Button(action: onRetry) {
                Label("Download from Google Drive", systemImage: "icloud.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.medium)
            }
            .buttonStyle(.borderedProminent)
        } else if item.syncStatus == .localOnly {
            if appContainer.auth.isAuthenticated {
                Button { performSyncAction() } label: {
                    Label("Back Up to Google Drive", systemImage: "icloud.and.arrow.up.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.medium)
                }
                .buttonStyle(.bordered)
            } else {
                Label("Connect Google Drive in Settings to back up this file.", systemImage: "iphone")
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    .frame(maxWidth: .infinity)
            }
        } else if item.syncStatus == .failed, appContainer.auth.isAuthenticated {
            Button { performSyncAction() } label: {
                Label("Retry Google Drive Sync", systemImage: "arrow.clockwise.icloud.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.medium)
            }
            .buttonStyle(.bordered)
        }
    }

    private var hasDescription: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var viewCountText: String {
        switch item.viewCount {
        case 0: "Never opened"
        case 1: "Opened once"
        default: "Opened \(item.viewCount) times"
        }
    }

    private var addTagChip: some View {
        Button { showTagPicker = true } label: {
            Label("Add Tag", systemImage: "plus")
                .font(AppTheme.Typography.caption1.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.accent)
                .padding(.horizontal, AppTheme.Spacing.medium)
                .frame(minHeight: 36)
                .background(AppTheme.Colors.accent.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Add or edit tags")
    }

    private func removableTagChip(_ tag: Tag) -> some View {
        Button { removeTag(tag) } label: {
            HStack(spacing: AppTheme.Spacing.xSmall) {
                TagSymbolView(sfSymbol: tag.sfSymbol, color: Color(hex: tag.colorHex), size: 11)
                Text(tag.name)
                    .font(AppTheme.Typography.caption1.weight(.medium))
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color(hex: tag.colorHex).opacity(0.75))
            }
            .foregroundStyle(Color(hex: tag.colorHex))
            .padding(.horizontal, AppTheme.Spacing.medium)
            .frame(minHeight: 36)
            .background(Color(hex: tag.colorHex).opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Remove \(tag.name) tag")
    }

    private func activityRow(
        symbol: String,
        title: String,
        primary: String,
        secondary: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 30, height: 30)
                .background(AppTheme.Colors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                Text(primary)
                    .font(AppTheme.Typography.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.label)
                if let secondary {
                    Text(secondary)
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func toggleDetails() {
        let expanded = !isDetailsExpanded
        if expanded {
            finishDescriptionEditing(clearFocus: true, collapseSheet: false)
        }
        withAnimation(AppTheme.Animation.snappy) {
            isDetailsExpanded = expanded
            selectedDetent = .fraction(expanded ? 0.60 : 0.45)
        }
    }

    private func beginAddingDescription() {
        withAnimation(AppTheme.Animation.snappy) {
            isAddingDescription = true
            isDetailsExpanded = false
            selectedDetent = .fraction(0.60)
        }
        focusedField = .description
    }

    private func finishEditing() {
        switch focusedField {
        case .title:
            commitTitle()
            focusedField = nil
        case .description:
            finishDescriptionEditing(clearFocus: true)
        case nil:
            break
        }
    }

    private func finishDescriptionEditing(clearFocus: Bool, collapseSheet: Bool = true) {
        commitDescription()
        if clearFocus { focusedField = nil }
        withAnimation(AppTheme.Animation.snappy) {
            isAddingDescription = false
            if collapseSheet && !isDetailsExpanded {
                selectedDetent = .fraction(0.45)
            }
        }
    }

    private func cancelDescriptionEditing() {
        descriptionText = descriptionBeforeEditing
        focusedField = nil
    }

    private func commitTitle() {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            titleText = item.title
            return
        }
        guard trimmed != item.title else { return }
        item.title = trimmed
        item.markModified()
        try? modelContext.save()
        HapticFeedback.light()
    }

    private func commitDescription() {
        let trimmed = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != item.itemDescription else { return }
        descriptionText = trimmed
        item.itemDescription = trimmed
        item.markModified()
        try? modelContext.save()
        HapticFeedback.light()
    }

    private func toggleTag(_ tag: Tag) {
        if item.tags.contains(where: { $0.id == tag.id }) {
            removeTag(tag)
        } else {
            item.tags.append(tag)
            item.markModified()
            try? modelContext.save()
            HapticFeedback.light()
        }
    }

    private func removeTag(_ tag: Tag) {
        item.tags.removeAll { $0.id == tag.id }
        item.markModified()
        try? modelContext.save()
        HapticFeedback.light()
    }

    private func saveWithHaptic() {
        try? modelContext.save()
        HapticFeedback.light()
    }

    private func performSyncAction() {
        if resolvedURL == nil {
            onRetry()
            return
        }
        guard appContainer.auth.isAuthenticated else { return }
        Task {
            if item.syncStatus == .localOnly {
                appContainer.sync.promoteLocalOnlyItems()
            } else if item.syncStatus == .failed {
                item.syncStatus = .pending
                try? modelContext.save()
            }
            await appContainer.sync.syncPendingItems()
        }
    }

    private func deleteItem() {
        isDeleting = true
        HapticFeedback.medium()
        Task {
            if let path = item.localFilePath {
                try? await appContainer.localStorage.delete(relativePath: path)
            }
            if let driveID = item.googleDriveFileID {
                try? await appContainer.drive.deleteFile(driveFileID: driveID)
            }
            modelContext.delete(item)
            do {
                try modelContext.save()
                onDelete()
            } catch {
                deleteError = error
                isDeleting = false
                HapticFeedback.error()
            }
        }
    }

}

// MARK: - Tag picker sheet

struct TagPickerSheet: View {
    let item: Item
    var onToggle: (Tag) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var allTags: [Tag] = []
    @State private var searchText = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredTags: [Tag] {
        guard !trimmedSearchText.isEmpty else { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearchText) }
    }

    private var canCreate: Bool {
        !trimmedSearchText.isEmpty &&
        !allTags.contains { $0.name.caseInsensitiveCompare(trimmedSearchText) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if canCreate {
                    Button(action: createTag) {
                        Label("Create \"\(trimmedSearchText)\"", systemImage: "plus.circle.fill")
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                }
                if filteredTags.isEmpty && !canCreate {
                    Text(allTags.isEmpty ? "No tags created yet." : "No tags match your search.")
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredTags) { tag in
                        Button {
                            onToggle(tag)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.medium) {
                                TagSymbolView(sfSymbol: tag.sfSymbol, color: Color(hex: tag.colorHex), size: 14)
                                    .frame(width: 22, height: 22)
                                    .background(Color(hex: tag.colorHex).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(tag.name)
                                    .foregroundStyle(AppTheme.Colors.label)
                                Spacer()
                                if isSelected(tag) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.Colors.accent)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                                }
                            }
                        }
                        .accessibilityLabel(tag.name)
                        .accessibilityValue(isSelected(tag) ? "Selected" : "Not selected")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search or create tag...")
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                allTags = ((try? modelContext.fetch(FetchDescriptor<Tag>(
                    sortBy: [SortDescriptor(\.name)]
                ))) ?? [])
            }
        }
    }

    private func isSelected(_ tag: Tag) -> Bool {
        item.tags.contains(where: { $0.id == tag.id })
    }

    private func createTag() {
        guard canCreate else { return }
        let colors = ["#3498DB", "#E74C3C", "#2ECC71", "#F39C12", "#9B59B6", "#1ABC9C"]
        let hex = colors.randomElement() ?? "#3498DB"
        let tag = Tag(name: trimmedSearchText, colorHex: hex, sfSymbol: "tag.fill")
        modelContext.insert(tag)
        allTags.append(tag)
        allTags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try? modelContext.save()
        onToggle(tag)
        searchText = ""
    }
}

// MARK: - Simple flow layout for tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var verticalSpacing: CGFloat? = nil

    private var resolvedVerticalSpacing: CGFloat {
        verticalSpacing ?? spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                height += rowHeight + resolvedVerticalSpacing
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
                y += rowHeight + resolvedVerticalSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
