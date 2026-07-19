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
                                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.7),
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
            viewModel.pendingUpload = pendingUpload
            viewModel.title = pendingUpload.suggestedTitle
        }
        .onChange(of: viewModel.savedItem) { _, item in
            guard item != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.0))
                dismiss()
                onComplete()
            }
        }
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xLarge) {
                // Full-width file preview
                filePreview
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xLarge, style: .continuous))
                    .padding(.horizontal, AppTheme.Spacing.base)
                    .task {
                        guard pendingUpload.fileType == .image else { return }
                        let data = pendingUpload.data
                        previewImage = await Task.detached(priority: .userInitiated) {
                            guard let thumbData = ThumbnailCache.makeThumbnailData(data) else { return nil }
                            return UIImage(data: thumbData)
                        }.value
                    }

                VStack(spacing: AppTheme.Spacing.medium) {
                    // Title
                    formCard {
                        TextField("Title", text: $viewModel.title)
                            .font(AppTheme.Typography.title3)
                    }

                    // Tags
                    formCard {
                        HStack {
                            Text("Tags")
                                .font(AppTheme.Typography.subheadline)
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            Spacer()
                            Button("Add Tag") { showTagPicker = true }
                                .font(AppTheme.Typography.subheadline)
                                .tint(AppTheme.Colors.accent)
                        }
                        if !viewModel.selectedTags.isEmpty {
                            FlowLayout(spacing: AppTheme.Spacing.small) {
                                ForEach(Array(viewModel.selectedTags).sorted { $0.name < $1.name }) { tag in
                                    TagChipView(tag: tag, isSelected: true) {
                                        viewModel.toggleTag(tag)
                                    }
                                }
                            }
                        }
                    }

                    // Notes
                    if viewModel.showNotes {
                        formCard {
                            TextEditor(text: $viewModel.itemDescription)
                                .font(AppTheme.Typography.body)
                                .frame(minHeight: 120)
                                .scrollContentBackground(.hidden)
                        }
                    } else {
                        Button {
                            withAnimation(AppTheme.Animation.fast) {
                                viewModel.showNotes = true
                            }
                        } label: {
                            Label("Add notes", systemImage: "plus.circle")
                                .font(AppTheme.Typography.subheadline)
                                .tint(AppTheme.Colors.accent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Spacing.base)
                    }
                }
                .padding(.bottom, AppTheme.Spacing.base)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task {
                    await viewModel.save(
                        context: modelContext,
                        sync: appContainer.sync,
                        localStorage: appContainer.localStorage,
                        isAuthenticated: appContainer.auth.isAuthenticated
                    )
                }
            } label: {
                Text("Save")
                    .font(AppTheme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.small)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.Colors.accent)
            .disabled(viewModel.title.isEmpty)
            .padding(.horizontal, AppTheme.Spacing.base)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(AppTheme.Colors.groupedBG)
        }
        .background(AppTheme.Colors.groupedBG)
    }

    // MARK: - Saving overlay (spinner while isSaving)

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            VStack(spacing: AppTheme.Spacing.medium) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppTheme.Colors.accent)
                Text("Saving to vault…")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
        }
    }

    // MARK: - Success toast

    private var successToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppTheme.Colors.syncSynced)
            Text("Saved!")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.label)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.Colors.secondaryBG,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
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

    // MARK: - File preview

    @ViewBuilder
    private var filePreview: some View {
        if pendingUpload.fileType == .image {
            ZStack {
                AppTheme.Colors.tertiaryBG
                if let uiImage = previewImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                }
            }
        } else {
            ZStack {
                AppTheme.Colors.secondaryBG
                VStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: pendingUpload.fileType.sfSymbol)
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(pendingUpload.fileType.tintColor)
                    Text(pendingUpload.fileName)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Form card helper

    @ViewBuilder
    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            content()
        }
        .padding(AppTheme.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.secondaryBG)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        .padding(.horizontal, AppTheme.Spacing.base)
    }
}

// MARK: - Tag picker sheet

struct MultiTagPickerSheet: View {

    @Binding var selectedTags: Set<Tag>

    @Query private var allTags: [Tag]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    TextField("Search tags...", text: $searchText)
                }
                .padding(AppTheme.Spacing.medium)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                .padding(AppTheme.Spacing.base)

                // Selected tags
                if !selectedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.small) {
                            ForEach(Array(selectedTags).sorted { $0.name < $1.name }) { tag in
                                TagChipView(tag: tag, isSelected: true) {
                                    selectedTags.remove(tag)
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.base)
                    }
                    .padding(.bottom, AppTheme.Spacing.small)
                }

                // Tag list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let filtered = filteredTags
                        let canCreate = !searchText.isEmpty &&
                            !filtered.contains { $0.name.lowercased() == searchText.lowercased() }

                        if filtered.isEmpty && !canCreate {
                            EmptyStateView(
                                symbol: "tag.slash",
                                title: "No tags found",
                                subtitle: "Type a name above to create a new tag."
                            )
                        } else {
                            if canCreate {
                                createTagRow(name: searchText)
                                Divider().padding(.leading, 56)
                            }
                            ForEach(filtered.sorted { $0.name < $1.name }) { tag in
                                tagRow(tag)
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .background(AppTheme.Colors.secondaryBG)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                    .padding(.horizontal, AppTheme.Spacing.base)
                }
            }
            .background(AppTheme.Colors.groupedBG)
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var filteredTags: [Tag] {
        if searchText.isEmpty { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func createTagRow(name: String) -> some View {
        let colors = ["#3498DB", "#E74C3C", "#2ECC71", "#F39C12", "#9B59B6", "#1ABC9C"]
        return HStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.Colors.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Create \"\(name)\"")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.accent)
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.base)
        .padding(.vertical, AppTheme.Spacing.medium)
        .contentShape(Rectangle())
        .onTapGesture {
            let hex = colors.randomElement() ?? "#3498DB"
            let tag = Tag(name: name, colorHex: hex, sfSymbol: "tag.fill")
            modelContext.insert(tag)
            try? modelContext.save()
            selectedTags.insert(tag)
            searchText = ""
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isSelected = selectedTags.contains(tag)
        return HStack(spacing: AppTheme.Spacing.medium) {
            TagSymbolView(sfSymbol: tag.sfSymbol, color: Color(hex: tag.colorHex), size: 16)
                .frame(width: 28, height: 28)
                .background(Color(hex: tag.colorHex).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(tag.name)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.label)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.Colors.accent)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.base)
        .padding(.vertical, AppTheme.Spacing.medium)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedTags.remove(tag)
            } else {
                selectedTags.insert(tag)
            }
        }
    }
}
