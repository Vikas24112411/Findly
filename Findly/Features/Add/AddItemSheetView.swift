import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Bottom sheet that lets users choose what type of content to add.
struct AddItemSheetView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.modelContext) private var modelContext

    // Source selection
    @State private var showPhotosPicker = false
    @State private var fileImportMode: FileImportMode? = nil
    @State private var showNoteComposer = false
    @State private var showLinkComposer = false
    @State private var showCameraPicker = false
    @State private var showAudioRecorder = false

    // Multi-file import
    @State private var importedURLs: [URL] = []
    @State private var showQuickImport = false

    // Upload flow
    @State private var pendingUpload: PendingUpload? = nil

    // Photos
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(AppTheme.Colors.tertiaryLabel.opacity(0.5))
                    .frame(width: 36, height: 5)
                    .padding(.top, AppTheme.Spacing.medium)
                    .padding(.bottom, AppTheme.Spacing.large)

                Text("Add to Vault")
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.label)
                    .padding(.bottom, AppTheme.Spacing.xLarge)

                // Type grid
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: AppTheme.Spacing.base
                ) {
                    ForEach(AddOption.allCases) { option in
                        addOptionButton(option)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.large)

                Spacer()
            }
            .background(AppTheme.Colors.groupedBG)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        // Photos picker
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $selectedPhotoItem,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await handlePhotoPickerItem(item)
            }
        }
        // Unified document / files-app importer
        .fileImporter(
            isPresented: Binding(
                get: { fileImportMode != nil },
                set: { if !$0 { fileImportMode = nil } }
            ),
            allowedContentTypes: [.item],
            allowsMultipleSelection: fileImportMode == .multi
        ) { result in
            let mode = fileImportMode
            fileImportMode = nil
            if case .success(let urls) = result {
                if mode == .multi, !urls.isEmpty {
                    importedURLs = urls
                    showQuickImport = true
                } else if let url = urls.first {
                    Task { await handleDocumentURL(url) }
                }
            }
        }
        .sheet(isPresented: $showQuickImport) {
            QuickImportView(urls: importedURLs) { dismiss() }
                .environment(appContainer)
        }
        // Upload flow sheet
        .sheet(item: $pendingUpload) { upload in
            ItemFormView(pendingUpload: upload) {
                dismiss()   // close AddItemSheetView; pendingUpload clears on sheet dismiss
            }
            .environment(appContainer)
        }
        // Note composer
        .sheet(isPresented: $showNoteComposer) {
            NoteComposerView { title, content in
                let data = content.data(using: .utf8) ?? Data()
                pendingUpload = PendingUpload(
                    data: data,
                    fileName: "\(title).txt",
                    fileType: .note,
                    suggestedTitle: title
                )
                showNoteComposer = false
            }
            .environment(appContainer)
        }
        // Link composer
        .sheet(isPresented: $showLinkComposer) {
            LinkComposerView { title, urlString in
                let data = urlString.data(using: .utf8) ?? Data()
                pendingUpload = PendingUpload(
                    data: data,
                    fileName: "\(title).webloc",
                    fileType: .link,
                    suggestedTitle: title
                )
                showLinkComposer = false
            }
        }
        // Audio recorder
        .sheet(isPresented: $showAudioRecorder) {
            AudioRecorderView(
                onResult: { data in
                    showAudioRecorder = false
                    let dateStamp = Date().fullDateString
                    pendingUpload = PendingUpload(
                        data: data,
                        fileName: "recording_\(UUID().uuidString).m4a",
                        fileType: .audio,
                        suggestedTitle: "Voice Memo — \(dateStamp)"
                    )
                },
                onCancel: {
                    showAudioRecorder = false
                }
            )
        }
        // Camera capture
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPickerView(
                onResult: { result in
                    showCameraPicker = false
                    Task { await handleCameraResult(result) }
                },
                onCancel: {
                    showCameraPicker = false
                }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Option button

    private func addOptionButton(_ option: AddOption) -> some View {
        Button {
            handleOption(option)
        } label: {
            VStack(spacing: AppTheme.Spacing.small) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .fill(option.fileType.tintColor.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: option.customSymbol ?? option.fileType.addSheetSymbol)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(option.fileType.tintColor)
                }
                Text(option.label)
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Option handling

    private func handleOption(_ option: AddOption) {
        switch option {
        case .photo:     showPhotosPicker = true
        case .document:  fileImportMode = .single
        case .filesApp:  fileImportMode = .multi
        case .note:      showNoteComposer = true
        case .link:      showLinkComposer = true
        case .camera:    showCameraPicker = true
        case .audio:     showAudioRecorder = true
        }
    }

    // MARK: - Photo handling

    private func handlePhotoPickerItem(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let isVideo = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) })
        let fileType: FileType = isVideo ? .video : .image
        let ext = isVideo ? "mp4" : "jpg"
        let name = item.itemIdentifier ?? UUID().uuidString

        await MainActor.run {
            pendingUpload = PendingUpload(
                data: data,
                fileName: "\(name).\(ext)",
                fileType: fileType,
                suggestedTitle: isVideo ? "Video" : "Photo"
            )
        }
    }

    // MARK: - Camera handling

    private func handleCameraResult(_ result: CameraResult) async {
        let dateStamp = Date().fullDateString
        switch result {
        case .photo(let image):
            guard let data = image.jpegData(compressionQuality: 0.9) else { return }
            await MainActor.run {
                pendingUpload = PendingUpload(
                    data: data,
                    fileName: "camera_\(UUID().uuidString).jpg",
                    fileType: .image,
                    suggestedTitle: "Camera Photo — \(dateStamp)"
                )
            }
        case .video(let url):
            let videoSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            await MainActor.run {
                pendingUpload = PendingUpload(
                    data: Data(),
                    fileName: "camera_\(UUID().uuidString).mp4",
                    fileType: .video,
                    suggestedTitle: "Camera Video — \(dateStamp)",
                    fileSize: videoSize,
                    sourceURL: url
                )
            }
        }
    }

    // MARK: - Document handling

    private func handleDocumentURL(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension
        let ft = FileType.detect(fileExtension: ext)

        await MainActor.run {
            pendingUpload = PendingUpload(
                data: data,
                fileName: url.lastPathComponent,
                fileType: ft,
                suggestedTitle: url.deletingPathExtension().lastPathComponent
            )
        }
    }
}

// MARK: - File import mode

private enum FileImportMode: Equatable {
    case single, multi
}

// MARK: - Add option enum

enum AddOption: String, CaseIterable, Identifiable {
    case photo, document, filesApp, note, link, camera, audio

    var id: String { rawValue }
    var label: String {
        switch self {
        case .photo:    return "Photo / Video"
        case .document: return "File"
        case .filesApp: return "Import Files"
        case .note:     return "Note"
        case .link:     return "Link"
        case .camera:   return "Camera"
        case .audio:    return "Record Audio"
        }
    }
    var fileType: FileType {
        switch self {
        case .photo:    return .image
        case .document: return .document
        case .filesApp: return .archive
        case .note:     return .note
        case .link:     return .link
        case .camera:   return .image
        case .audio:    return .audio
        }
    }
    var customSymbol: String? {
        switch self {
        case .filesApp: return "folder.badge.plus"
        case .camera:   return "camera.fill"
        case .audio:    return nil
        default: return nil
        }
    }
}

// MARK: - Pending upload model

struct PendingUpload: Identifiable {
    let id = UUID()
    let data: Data
    let fileName: String
    let fileType: FileType
    let suggestedTitle: String
    var fileSize: Int64? = nil   // overrides data.count when set (e.g. for video sourceURL)
    var sourceURL: URL? = nil   // set for large files (video) to avoid loading into memory
}

// MARK: - Note composer

struct NoteComposerView: View {
    var onCreate: (String, String) -> Void
    @State private var title = ""
    @State private var content = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var appContainer
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Title", text: $title)
                    .font(AppTheme.Typography.title2)
                    .padding(AppTheme.Spacing.base)
                Divider()
                TextEditor(text: $content)
                    .font(AppTheme.Typography.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .padding(AppTheme.Spacing.base)
            }
            .onAppear { isFocused = true }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") {
                        guard !title.isEmpty else { return }
                        onCreate(title, content)
                    }
                    .disabled(title.isEmpty)
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { isFocused = false }
                }
            }
        }
    }
}

// MARK: - Link composer

struct LinkComposerView: View {
    var onCreate: (String, String) -> Void
    @State private var title = ""
    @State private var urlString = ""
    @Environment(\.dismiss) private var dismiss

    private var isValidURL: Bool {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme, !scheme.isEmpty,
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("e.g. Apple", text: $title) }
                Section {
                    TextField("https://...", text: $urlString).keyboardType(.URL).autocorrectionDisabled()
                    if !urlString.isEmpty && !isValidURL {
                        Text("Please enter a valid URL (e.g. https://...)")
                            .font(AppTheme.Typography.caption1)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("URL")
                }
            }
            .navigationTitle("New Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") {
                        guard !title.isEmpty, isValidURL else { return }
                        onCreate(title, urlString)
                    }
                    .disabled(title.isEmpty || !isValidURL)
                }
            }
        }
    }
}
