import SwiftUI
import SwiftData

/// Single-screen form for adding metadata to a pending upload.
struct ItemFormView: View {

    let pendingUpload: PendingUpload
    var onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = ItemFormViewModel()
    @State private var showTagPicker = false
    @State private var previewImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.saveError != nil {
                    savingView
                } else {
                    formView
                        .overlay {
                            if viewModel.isSaving {
                                savingOverlay
                            }
                        }
                        .overlay {
                            if viewModel.savedItem != nil {
                                successToast
                                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                            }
                        }
                        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                                   value: viewModel.savedItem != nil)
                        .animation(.easeInOut(duration: 0.15), value: viewModel.isSaving)
                }
            }
            .navigationTitle("Add to Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !viewModel.isSaving && viewModel.savedItem == nil {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .sheet(isPresented: $showTagPicker) {
                MultiTagPickerSheet(selectedTags: $viewModel.selectedTags)
                    .environment(\.modelContext, modelContext)
            }
        }
        .onAppear {
            guard viewModel.pendingUpload == nil else { return }
            viewModel.pendingUpload = pendingUpload
            viewModel.title = pendingUpload.suggestedTitle
        }
        .task(id: viewModel.savedItem?.id) {
            guard viewModel.savedItem != nil else { return }
            UIAccessibility.post(notification: .announcement, argument: "Saved to Findly")
            // A brief, cancellable confirmation before returning to the vault.
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            dismiss()
            onComplete()
        }
    }

    // MARK: - Form

    private var formView: some View {
        AddToVaultForm(
            fileName: pendingUpload.fileName, fileType: pendingUpload.fileType, previewImage: previewImage,
            title: $viewModel.title, notes: $viewModel.itemDescription, showNotes: $viewModel.showNotes,
            selectedTags: viewModel.selectedTags.map { $0.vaultTagOption },
            isSaving: viewModel.isSaving, isSaved: viewModel.savedItem != nil,
            addTag: { showTagPicker = true },
            removeTag: { id in
                if let tag = viewModel.selectedTags.first(where: { $0.id == id }) { viewModel.toggleTag(tag) }
            },
            save: { Task { await save() } }
        )
        .task {
            guard pendingUpload.fileType == .image else { return }
            let data = pendingUpload.data
            previewImage = await Task.detached(priority: .userInitiated) {
                guard let thumbData = ThumbnailCache.makeThumbnailData(data) else { return nil }
                return UIImage(data: thumbData)
            }.value
        }
    }

    private var savingOverlay: some View { VaultSavingOverlay() }
    private var successToast: some View { VaultSavedToast() }

    private func save() async {
        await viewModel.save(context: modelContext, sync: appContainer.sync,
                             localStorage: appContainer.localStorage,
                             isAuthenticated: appContainer.auth.isAuthenticated)
    }

    // MARK: - Error view (full-screen, for retry flow)

    private var savingView: some View {
        EmptyStateView(
            symbol: "exclamationmark.circle",
            title: "Save Failed",
            subtitle: viewModel.saveError?.localizedDescription ?? "Something went wrong.",
            actionLabel: "Try Again"
        ) {
            Task {
                await viewModel.save(
                    context: modelContext,
                    sync: appContainer.sync,
                    localStorage: appContainer.localStorage,
                    isAuthenticated: appContainer.auth.isAuthenticated
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

extension Tag {
    var vaultTagOption: VaultTagOption {
        VaultTagOption(id: id, name: name, colorHex: colorHex, sfSymbol: sfSymbol)
    }
}

/// SwiftData adapter for the same picker used by the share extension.
struct MultiTagPickerSheet: View {
    @Binding var selectedTags: Set<Tag>
    @Query private var allTags: [Tag]
    @Environment(\.modelContext) private var modelContext
    @State private var saveError: String?

    var body: some View {
        VaultTagPicker(tags: allTags.map { $0.vaultTagOption }, selectedIDs: Binding(
            get: { Set(selectedTags.map(\.id)) },
            set: { ids in selectedTags = Set(allTags.filter { ids.contains($0.id) }) }
        )) { name in
            let tag = Tag(name: name)
            modelContext.insert(tag)
            do {
                try modelContext.save()
                selectedTags.insert(tag)
            } catch {
                modelContext.delete(tag)
                saveError = error.localizedDescription
            }
        }
        .alert("Couldn’t Create Tag", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) { Button("OK") { saveError = nil } } message: { Text(saveError ?? "") }
    }
}
