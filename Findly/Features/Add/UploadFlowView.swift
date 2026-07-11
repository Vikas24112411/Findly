import SwiftUI
import SwiftData

/// Multi-step upload wizard.
/// Steps: Preview → Title → Tags → Description → Saving
struct UploadFlowView: View {

    let pendingUpload: PendingUpload
    var onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = UploadFlowViewModel()

    @Query private var allTags: [Tag]

    var body: some View {
        NavigationStack {
            TabView(selection: $viewModel.currentStep) {
                previewStep.tag(UploadFlowViewModel.Step.preview)
                titleStep.tag(UploadFlowViewModel.Step.title)
                tagsStep.tag(UploadFlowViewModel.Step.tags)
                descriptionStep.tag(UploadFlowViewModel.Step.description)
                savingStep.tag(UploadFlowViewModel.Step.saving)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(AppTheme.Animation.fast, value: viewModel.currentStep)
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(viewModel.currentStep == .saving)
        }
        .onAppear {
            viewModel.pendingUpload = pendingUpload
            viewModel.title = pendingUpload.suggestedTitle
        }
    }

    // MARK: - Steps

    private var previewStep: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xLarge) {
                // File preview
                filePreview
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xLarge, style: .continuous))

                // File info card
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    infoRow("File name", pendingUpload.fileName)
                    infoRow("Type", pendingUpload.fileType.displayName)
                    infoRow("Size", Int64(pendingUpload.data.count).fileSizeString)
                }
                .padding(AppTheme.Spacing.base)
                .background(AppTheme.Colors.secondaryBG)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
            }
            .padding(AppTheme.Spacing.base)
        }
    }

    private var titleStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                Text("Give it a name")
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.label)

                TextField("Title", text: $viewModel.title)
                    .font(AppTheme.Typography.title3)
                    .padding(AppTheme.Spacing.base)
                    .background(AppTheme.Colors.secondaryBG)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
            }
            .padding(AppTheme.Spacing.base)
        }
    }

    private var tagsStep: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                TextField("Search tags...", text: $viewModel.tagSearchText)
            }
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.Colors.secondaryBG)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
            .padding(AppTheme.Spacing.base)

            // Selected tags
            if !viewModel.selectedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        ForEach(Array(viewModel.selectedTags).sorted { $0.name < $1.name }) { tag in
                            TagChipView(tag: tag, isSelected: true) {
                                viewModel.toggleTag(tag)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.base)
                }
                .padding(.bottom, AppTheme.Spacing.small)
            }

            // All tags list
            ScrollView {
                LazyVStack(spacing: 0) {
                    let filtered = viewModel.filteredTags(from: allTags)
                    let canCreate = !viewModel.tagSearchText.isEmpty &&
                        !filtered.contains { $0.name.lowercased() == viewModel.tagSearchText.lowercased() }
                    if filtered.isEmpty && !canCreate {
                        EmptyStateView(
                            symbol: "tag.slash",
                            title: "No tags found",
                            subtitle: "Type a name above to create a new tag."
                        )
                    } else {
                        if canCreate {
                            createTagRow(name: viewModel.tagSearchText)
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
    }

    private var descriptionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                Text("Add a description")
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.label)
                Text("Optional — helps you find this item later.")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                TextEditor(text: $viewModel.itemDescription)
                    .font(AppTheme.Typography.body)
                    .frame(minHeight: 140)
                    .padding(AppTheme.Spacing.medium)
                    .background(AppTheme.Colors.secondaryBG)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
            }
            .padding(AppTheme.Spacing.base)
        }
    }

    private var savingStep: some View {
        VStack(spacing: AppTheme.Spacing.xLarge) {
            if viewModel.isSaving {
                VStack(spacing: AppTheme.Spacing.xLarge) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(AppTheme.Colors.accent)
                    Text("Saving to vault…")
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
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
                VStack(spacing: AppTheme.Spacing.xLarge) {
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
                        dismiss()       // close UploadFlowView
                        onComplete()    // close AddItemSheetView
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.Colors.accent)
                    .font(AppTheme.Typography.headline)
                    .padding(.horizontal, AppTheme.Spacing.xxLarge)
                }
                .onAppear {
                    // Auto-dismiss after 2 s so the sheet closes even if Done isn't tapped
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        dismiss()
                        onComplete()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !viewModel.isSaving, viewModel.savedItem == nil, viewModel.saveError == nil else { return }
            await viewModel.save(
                context: modelContext,
                sync: appContainer.sync,
                localStorage: appContainer.localStorage,
                isAuthenticated: appContainer.auth.isAuthenticated
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if viewModel.currentStep != .saving {
                Button("Cancel") { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if viewModel.currentStep < .description {
                Button("Next") { viewModel.advance() }
                    .disabled(viewModel.currentStep == .title && viewModel.title.isEmpty)
            } else if viewModel.currentStep == .description {
                Button("Save") { viewModel.advance() }
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if viewModel.currentStep > .preview && viewModel.currentStep != .saving {
                Button("Back") { viewModel.goBack() }
            }
        }
    }

    // MARK: - Step indicator helpers

    private var stepTitle: String {
        switch viewModel.currentStep {
        case .preview:     return "Preview"
        case .title:       return "Title"
        case .tags:        return "Tags"
        case .description: return "Description"
        case .saving:      return "Saving"
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var filePreview: some View {
        let data = pendingUpload.data
        if pendingUpload.fileType == .image, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
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

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
            Spacer()
            Text(value)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.label)
                .lineLimit(1)
        }
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
            viewModel.toggleTag(tag)
            viewModel.tagSearchText = ""
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isSelected = viewModel.selectedTags.contains(tag)
        return HStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: tag.sfSymbol)
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: tag.colorHex))
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
        .onTapGesture { viewModel.toggleTag(tag) }
    }
}
