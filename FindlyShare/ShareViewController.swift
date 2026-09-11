import SwiftUI
import LocalAuthentication

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let controller = UIHostingController(rootView: ShareSaveView(providers: providers, finish: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }, cancel: { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }))
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        isModalInPresentation = true
    }
}

@MainActor
@Observable
private final class ShareSaveModel {
    enum Phase { case loading, editing, saving, saved, failed }
    var phase = Phase.loading
    var file: LoadedShareFile?
    var title = ""
    var notes = ""
    var tags: [SharedTag] = []
    var selectedTags = Set<UUID>()
    var newTags: [VaultTagOption] = []
    var showNotes = false
    var appearanceMode: String?
    var previewImage: UIImage?
    var errorMessage: String?
    private var inbox: ShareInbox?
    private let id = UUID()

    func load(_ providers: [NSItemProvider]) async {
        guard phase == .loading || phase == .failed else { return }
        phase = .loading
        errorMessage = nil
        do {
            let inbox = try ShareInbox()
            let catalog = try await Task.detached { try inbox.catalog() }.value
            if catalog.requiresUnlock || UserDefaults(suiteName: ShareInbox.groupID)?.bool(forKey: "appLockEnabled") == true {
                let context = LAContext()
                let unlocked = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Add a file to your Findly vault")
                guard unlocked else { throw CocoaError(.userCancelled) }
            }
            try Task.checkCancellation()
            let file = try await SharedAttachmentLoader.load(providers)
            self.file = file
            self.inbox = inbox
            appearanceMode = catalog.appearanceMode
            if FileType.detect(fileExtension: (file.name as NSString).pathExtension) == .image {
                previewImage = await Task.detached(priority: .userInitiated) { VaultPreview.image(at: file.url) }.value
            }
            try Task.checkCancellation()
            tags = catalog.tags
            title = file.suggestedTitle ?? (file.name as NSString).deletingPathExtension
            if title.isEmpty { title = file.name }
            phase = .editing
        } catch {
            if Task.isCancelled { cleanup() }
            if !Task.isCancelled {
                errorMessage = (error as NSError).code == NSFileReadNoSuchFileError
                    ? ShareError.unavailable.localizedDescription : error.localizedDescription
                phase = .failed
            }
        }
    }

    func save() async {
        guard phase == .editing, let file, let inbox else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        phase = .saving
        errorMessage = nil
        let metadata = SharedFile(id: id, originalName: file.name, title: cleanTitle, notes: notes,
                                  tagIDs: tags.filter { selectedTags.contains($0.id) }.map(\.id),
                                  newTagNames: newTags.filter { selectedTags.contains($0.id) }.map(\.name), createdAt: Date())
        do {
            try await Task.detached { try inbox.enqueue(source: file.url, file: metadata) }.value
            phase = .saved
        } catch {
            errorMessage = error.localizedDescription
            phase = .editing
        }
    }

    func createTag(named name: String) {
        let tag = VaultTagOption(id: UUID(), name: name)
        newTags.append(tag)
        selectedTags.insert(tag.id)
    }

    func cleanup() {
        if let file { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        file = nil
    }
}

private struct ShareSaveView: View {
    let providers: [NSItemProvider]
    let finish: () -> Void
    let cancel: () -> Void
    @State private var model = ShareSaveModel()
    @State private var showTagPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tagOptions: [VaultTagOption] {
        model.tags.map {
            VaultTagOption(id: $0.id, name: $0.name, colorHex: $0.colorHex ?? "#4A90E2", sfSymbol: $0.sfSymbol ?? "tag.fill")
        } + model.newTags
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView("Preparing file…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed:
                    ContentUnavailableView {
                        Label("Couldn’t Load File", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(model.errorMessage ?? "Try sharing the file again.")
                    } actions: {
                        Button("Try Again") { Task { await model.load(providers) } }
                    }
                case .editing, .saving, .saved:
                    form
                        .overlay {
                            if model.phase == .saving { VaultSavingOverlay() }
                            if model.phase == .saved {
                                VaultSavedToast()
                                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                            }
                        }
                        .animation(reduceMotion ? nil : AppTheme.Animation.fast, value: model.phase == .saved)
                }
            }
            .background(AppTheme.Colors.groupedBG)
            .navigationTitle("Add to Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.phase != .saved && model.phase != .saving {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            model.cleanup()
                            cancel()
                        }
                    }
                }
            }
            .sheet(isPresented: $showTagPicker) {
                VaultTagPicker(tags: tagOptions, selectedIDs: $model.selectedTags) { name in
                    model.createTag(named: name)
                }
            }
            .alert("Save Failed", isPresented: Binding(
                get: { model.phase == .editing && model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("Try Again") { Task { await model.save() } }
                Button("Cancel", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
        .tint(AppTheme.Colors.accent)
        .preferredColorScheme(model.appearanceMode == "light" ? .light : model.appearanceMode == "dark" ? .dark : nil)
        .task { await model.load(providers) }
        .task(id: model.phase == .saved) {
            guard model.phase == .saved else { return }
            UIAccessibility.post(notification: .announcement, argument: "Saved to Findly")
            // Match the in-app confirmation duration, then return to the source app.
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            model.cleanup()
            finish()
        }
        .onDisappear {
            // A tag-picker presentation must never discard the attachment.
            if !showTagPicker && model.phase != .saving { model.cleanup() }
        }
    }

    @ViewBuilder
    private var form: some View {
        if let file = model.file {
            AddToVaultForm(
                fileName: file.name,
                fileType: FileType.detect(fileExtension: (file.name as NSString).pathExtension),
                previewImage: model.previewImage,
                textPreview: file.textPreview,
                title: $model.title, notes: $model.notes, showNotes: $model.showNotes,
                selectedTags: tagOptions.filter { model.selectedTags.contains($0.id) },
                isSaving: model.phase == .saving, isSaved: model.phase == .saved,
                footer: "Your saved item will appear in your vault when you next open Findly.",
                addTag: { showTagPicker = true },
                removeTag: { model.selectedTags.remove($0) },
                save: { Task { await model.save() } }
            )
        }
    }
}
