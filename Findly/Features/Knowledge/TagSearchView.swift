import SwiftUI
import SwiftData

struct TagSearchView: View {

    @Bindable var viewModel: KnowledgeViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    @State private var showCreateSheet = false
    @State private var renameTag: Tag? = nil
    @State private var createChildFor: Tag? = nil
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
        .sheet(item: $renameTag) { tag in
            NavigationStack {
                TagEditorView(editingTag: tag) { name, color, symbol in
                    viewModel.updateTag(tag, name: name, colorHex: color, sfSymbol: symbol)
                    renameTag = nil
                }
            }
        }
    }

    // MARK: - Suggestions (all root tags as a browsable list)

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if viewModel.rootTags.isEmpty {
                EmptyStateView(
                    symbol: "tag.slash",
                    title: "No tags",
                    subtitle: "Type a name to create one.",
                    placement: .page
                )
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

    // MARK: - Create tag row

    private func createTagRow(name: String) -> some View {
        let colors = ["#3498DB", "#E74C3C", "#2ECC71", "#F39C12", "#9B59B6", "#1ABC9C"]
        return Button {
            viewModel.createTag(
                name: name,
                colorHex: colors.randomElement() ?? "#3498DB",
                sfSymbol: "tag.fill"
            )
            viewModel.searchText = ""
        } label: {
            HStack(spacing: AppTheme.Spacing.medium) {
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
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered tag tree

    private var filteredTagTree: some View {
        let allTags = allNestedTags(from: viewModel.rootTags)
        return Group {
            if viewModel.filteredRootTags.isEmpty {
                VStack(spacing: 0) {
                    createTagRow(name: viewModel.searchText)
                    Divider().padding(.leading, 56)
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "No matches"
                    )
                }
                .background(AppTheme.Colors.secondaryBG)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                .padding(AppTheme.Spacing.base)
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
                                showCreateSheet = true
                            },
                            onRename: { tag in
                                renameTag = tag
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
        HStack(spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
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
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.full, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
            .animation(.easeInOut(duration: 0.15), value: viewModel.searchText.isEmpty)

            Button {
                viewModel.searchText = ""
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.base)
        .padding(.vertical, AppTheme.Spacing.small)
    }

    // MARK: - Create tag sheet

    @ViewBuilder
    private func createTagSheetView(parent: Tag?) -> some View {
        NavigationStack {
            TagEditorView(
                parentTag: parent,
                onSave: { name, color, symbol in
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
