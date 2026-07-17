import SwiftUI
import SwiftData

struct TagSearchView: View {

    @Bindable var viewModel: KnowledgeViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    @State private var showCreateSheet = false
    @State private var renameTag: Tag? = nil
    @State private var createChildFor: Tag? = nil
    @State private var newTagName: String = ""
    @State private var selectedTagForDetail: Tag? = nil
    @State private var tagToSetParentFor: Tag? = nil

    var body: some View {
        ScrollView {
            if viewModel.searchText.isEmpty {
                suggestionsSection
            } else {
                filteredTagTree
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { bottomSearchBar }
        .background(AppTheme.Colors.groupedBG)
        .navigationTitle("Search Tags")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.searchText = ""
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
            }
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.expandMatchingTags(query: newValue)
        }
        .onAppear { searchFocused = true }
        .sheet(item: $selectedTagForDetail) { tag in
            TagDetailSheet(tag: tag, items: viewModel.tagItems)
        }
        .sheet(isPresented: $showCreateSheet) {
            createTagSheetView(parent: createChildFor)
        }
        .sheet(item: $tagToSetParentFor) { tag in
            SetParentSheet(
                tag: tag,
                allTags: allNestedTags(from: viewModel.rootTags)
            ) { parent in
                if let parent {
                    viewModel.addParent(parent, to: tag)
                } else {
                    viewModel.makeTopLevel(tag)
                }
                tagToSetParentFor = nil
            }
        }
        .alert("Rename Tag", isPresented: Binding(
            get: { renameTag != nil },
            set: { if !$0 { renameTag = nil } }
        )) {
            TextField("Tag name", text: $newTagName)
            Button("Rename") {
                if let tag = renameTag, !newTagName.isEmpty {
                    viewModel.renameTag(tag, to: newTagName)
                }
                renameTag = nil
            }
            Button("Cancel", role: .cancel) { renameTag = nil }
        }
    }

    // MARK: - Suggestions (all root tags as a browsable list)

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if viewModel.rootTags.isEmpty {
                EmptyStateView(
                    symbol: "tag.slash",
                    title: "No tags yet",
                    subtitle: "Create tags to organize your vault."
                )
                .padding(.top, AppTheme.Spacing.xxxLarge)
            } else {
                SectionHeader(title: "All Tags")
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.rootTags) { tag in
                        Button {
                            viewModel.searchText = tag.name
                        } label: {
                            HStack(spacing: AppTheme.Spacing.medium) {
                                TagSymbolView(sfSymbol: tag.sfSymbol, color: Color(hex: tag.colorHex), size: 14)
                                    .frame(width: 22, height: 22)
                                    .background(Color(hex: tag.colorHex).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(tag.name)
                                    .foregroundStyle(AppTheme.Colors.label)
                                    .font(AppTheme.Typography.body)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                            }
                            .padding(.horizontal, AppTheme.Spacing.base)
                            .padding(.vertical, AppTheme.Spacing.medium)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, AppTheme.Spacing.base)
                    }
                }
                .background(AppTheme.Colors.secondaryBG)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                .padding(.horizontal, AppTheme.Spacing.base)
            }
        }
        .padding(.vertical, AppTheme.Spacing.large)
    }

    // MARK: - Filtered tag tree

    private var filteredTagTree: some View {
        let allTags = allNestedTags(from: viewModel.rootTags)
        return Group {
            if viewModel.filteredRootTags.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "No tags found",
                    subtitle: "No tags match \"\(viewModel.searchText)\"."
                )
                .padding(.top, AppTheme.Spacing.xxxLarge)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredRootTags) { tag in
                        TagNodeView(
                            tag: tag,
                            depth: 0,
                            allTags: allTags,
                            expandedIDs: $viewModel.expandedTagIDs,
                            onSelect: { selected in
                                viewModel.selectTag(selected)
                                selectedTagForDetail = selected
                            },
                            onCreateChild: { parent in
                                createChildFor = parent
                                newTagName = ""
                                showCreateSheet = true
                            },
                            onRename: { tag in
                                renameTag = tag
                                newTagName = tag.name
                            },
                            onDelete: { tag in
                                viewModel.deleteTag(tag)
                            },
                            onSetParent: { tag in
                                tagToSetParentFor = tag
                            },
                            onMakeTopLevel: { tag in
                                viewModel.makeTopLevel(tag)
                            }
                        )
                        Divider().padding(.leading, AppTheme.Spacing.base)
                    }
                }
                .background(AppTheme.Colors.secondaryBG)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                .padding(AppTheme.Spacing.base)
            }
        }
    }

    // MARK: - Bottom search bar

    private var bottomSearchBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: AppTheme.Spacing.small) {
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(searchFocused ? AppTheme.Colors.accent : AppTheme.Colors.tertiaryLabel)
                    TextField("Search tags...", text: $viewModel.searchText)
                        .focused($searchFocused)
                        .submitLabel(.search)
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        }
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .padding(AppTheme.Spacing.small)
                .background(AppTheme.Colors.tertiaryBG)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(
                            searchFocused ? AppTheme.Colors.accent : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: searchFocused)
                .animation(.easeInOut(duration: 0.15), value: viewModel.searchText.isEmpty)
            }
            .padding(.horizontal, AppTheme.Spacing.base)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(.regularMaterial)
        }
    }

    // MARK: - Create tag sheet

    @ViewBuilder
    private func createTagSheetView(parent: Tag?) -> some View {
        NavigationStack {
            CreateTagView(
                parentTag: parent,
                onCreate: { name, color, symbol in
                    viewModel.createTag(name: name, colorHex: color, sfSymbol: symbol, parent: parent)
                    showCreateSheet = false
                }
            )
        }
    }

    // MARK: - Helpers

    private func allNestedTags(from tags: [Tag]) -> [Tag] {
        tags.flatMap { tag -> [Tag] in
            [tag] + allNestedTags(from: tag.children)
        }
    }
}
