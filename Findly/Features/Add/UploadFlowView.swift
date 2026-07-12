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

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isSaving || viewModel.savedItem != nil || viewModel.saveError != nil {
                    savingView
                } else {
                    formView
                }
            }
            .navigationTitle("Add to Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !viewModel.isSaving {
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

                    // Save button
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
                    .padding(.bottom, AppTheme.Spacing.base)
                }
            }
        }
        .background(AppTheme.Colors.groupedBG)
    }

    // MARK: - Saving / success / error

    private var savingView: some View {
        VStack(spacing: AppTheme.Spacing.xLarge) {
            if viewModel.isSaving {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppTheme.Colors.accent)
                Text("Saving to vault…")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            } else if let error = viewModel.saveError {
                EmptyStateView(
                    symbol: "exclamationmark.circle",
                    title: "Save Failed",
                    subtitle: error.localizedDescription,
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
            } else if viewModel.savedItem != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppTheme.Colors.syncSynced)
                Text("Saved!")
                    .font(AppTheme.Typography.title1)
                Text(appContainer.auth.isAuthenticated
                     ? "Your file is in your vault.\nUploading to Google Drive in the background."
                     : "Your file is saved on this device.\nConnect Google Drive in Settings to back it up.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .multilineTextAlignment(.center)
                Button("Done") {
                    dismiss()
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Colors.accent)
                .font(AppTheme.Typography.headline)
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.savedItem) { _, item in
            guard item != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                dismiss()
                onComplete()
            }
        }
    }

    // MARK: - File preview

    @ViewBuilder
    private var filePreview: some View {
        let data = pendingUpload.data
        if pendingUpload.fileType == .image, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .background(AppTheme.Colors.tertiaryBG)
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
                .background(AppTheme.Colors.secondaryBG)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
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
