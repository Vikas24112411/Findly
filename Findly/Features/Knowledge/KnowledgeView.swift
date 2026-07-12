import SwiftUI
import SwiftData

struct KnowledgeView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = KnowledgeViewModel()

    @State private var showCreateSheet = false
    @State private var renameTag: Tag? = nil
    @State private var createChildFor: Tag? = nil
    @State private var newTagName: String = ""
    @State private var selectedTagForDetail: Tag? = nil
    @State private var tagToSetParentFor: Tag? = nil
    @State private var scrollOffset: CGFloat = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.rootTags.isEmpty && viewModel.searchText.isEmpty {
                    emptyState
                } else {
                    tagTree
                }
            }
            .navTransitionTitle("Tags", progress: scrollProgress(from: scrollOffset))
            .onChange(of: viewModel.searchText) { _, newValue in
                viewModel.expandMatchingTags(query: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createChildFor = nil
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                }
            }
            .onAppear {
                viewModel.setup(context: modelContext)
            }
            .sheet(item: $selectedTagForDetail) { tag in
                TagDetailSheet(tag: tag, items: viewModel.tagItems)
            }
            .sheet(isPresented: $showCreateSheet) {
                createTagSheet(parent: createChildFor)
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
    }

    // MARK: - Tag tree

    private var tagTree: some View {
        ScrollView {
            VStack(spacing: 0) {
                LargeTitleHeader(title: "Tags", progress: scrollProgress(from: scrollOffset))
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    Section {
                        LazyVStack(spacing: 0) {
                            let allTags = allNestedTags(from: viewModel.rootTags)
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
                    } header: {
                        InlineSearchBar(
                            text: $viewModel.searchText,
                            prompt: "Search tags...",
                            isFocused: $searchFocused
                        )
                    }
                }
            }
        }
        .background(AppTheme.Colors.groupedBG)
        .trackScrollOffset($scrollOffset)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            symbol: "tag.slash",
            title: "No tags yet",
            subtitle: "Create tags to organize your knowledge into a searchable hierarchy.",
            actionLabel: "Create First Tag"
        ) {
            showCreateSheet = true
        }
    }

    // MARK: - Create tag sheet

    @ViewBuilder
    private func createTagSheet(parent: Tag?) -> some View {
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

// MARK: - Set Parent Sheet

struct SetParentSheet: View {
    let tag: Tag
    let allTags: [Tag]
    var onSelect: (Tag?) -> Void   // nil = make top-level

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label("Make Top-Level Tag", systemImage: "arrow.up.to.line")
                    }
                } footer: {
                    Text("Removes \"\(tag.name)\" from any parent and places it at the root level.")
                }

                Section("Move under...") {
                    ForEach(availableParents) { candidate in
                        Button {
                            onSelect(candidate)
                            dismiss()
                        } label: {
                            HStack(spacing: AppTheme.Spacing.medium) {
                                TagSymbolView(sfSymbol: candidate.sfSymbol, color: Color(hex: candidate.colorHex), size: 14)
                                    .frame(width: 22, height: 22)
                                    .background(Color(hex: candidate.colorHex).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(candidate.name)
                                        .foregroundStyle(AppTheme.Colors.label)
                                    if !candidate.children.isEmpty {
                                        Text("\(candidate.children.count) subtag\(candidate.children.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Set Parent for \"\(tag.name)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var availableParents: [Tag] {
        // Exclude self and all descendants (would create cycle)
        let excludedIDs = TagGraphTraverser.allDescendantIDs(of: tag)
        return allTags
            .filter { !excludedIDs.contains($0.id) }
            .sorted { $0.name < $1.name }
    }
}

// MARK: - Tag detail sheet

struct TagDetailSheet: View {
    let tag: Tag
    let items: [Item]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.medium) {
                    if items.isEmpty {
                        EmptyStateView(
                            symbol: "tray",
                            title: "No items",
                            subtitle: "No files are tagged with \"\(tag.name)\" or its descendants."
                        )
                        .padding(.top, AppTheme.Spacing.xxxLarge)
                    } else {
                        ForEach(items) { item in
                            NavigationLink(destination: ItemDetailView(item: item)) {
                                ItemCardView(item: item, style: .row)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, AppTheme.Spacing.base)
                        }
                    }
                }
                .padding(.vertical, AppTheme.Spacing.base)
            }
            .background(AppTheme.Colors.groupedBG)
            .navigationTitle(tag.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Create Tag View

struct CreateTagView: View {
    var parentTag: Tag?
    var onCreate: (String, String, String) -> Void

    @State private var name: String = ""
    @State private var colorHex: String = "#4A90E2"
    @State private var symbol: String = "tag.fill"
    @State private var showEmojis = false
    @State private var customColor: Color = Color(hex: "#4A90E2")
    @Environment(\.dismiss) private var dismiss

    private let presetColors = [
        "#4A90E2", "#E74C3C", "#2ECC71", "#F39C12",
        "#9B59B6", "#1ABC9C", "#E67E22", "#3498DB",
        "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
        "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F"
    ]

    private let presetSymbols = [
        "tag.fill", "folder.fill", "star.fill", "heart.fill",
        "book.fill", "briefcase.fill", "camera.fill", "music.note",
        "gamecontroller.fill", "house.fill", "car.fill", "airplane",
        "doc.fill", "chart.bar.fill", "bell.fill", "crown.fill",
        "bolt.fill", "flame.fill", "leaf.fill", "globe",
        "paintbrush.fill", "wrench.fill", "person.fill", "bag.fill",
        "cart.fill", "gift.fill", "map.fill", "magnifyingglass",
        "checkmark.circle.fill", "exclamationmark.circle.fill", "info.circle.fill", "lock.fill",
        "key.fill", "shield.fill", "cloud.fill", "moon.fill"
    ]

    private let presetEmojis = [
        "📁", "📄", "📝", "📌", "🔖", "📎", "🗂", "💼",
        "📊", "💡", "🔑", "🔐", "🎯", "⚙️", "🔧", "🖥",
        "📱", "💻", "🎨", "📷", "🎵", "🎬", "🏆", "🚀",
        "🌟", "⭐", "🌙", "☀️", "🌊", "🌳", "🌺", "🍀",
        "🔥", "❄️", "🌈", "🌍", "🌸", "🌿", "🦋", "🐾",
        "🍎", "🍕", "☕", "🍷", "🎂", "🍓", "🥑", "🍪",
        "❤️", "💛", "💚", "💙", "💜", "🖤", "✅", "❌",
        "⚡", "💰", "🎁", "🏷️", "🔔", "💬", "📧", "🔴",
        "🏃", "🏋️", "🎮", "✈️", "🚗", "🏠", "🏢", "🎭",
        "👤", "👥", "🤝", "👋", "🙌", "💪", "🧠", "👁"
    ]

    var body: some View {
        Form {
            Section {
                TextField("Tag name", text: $name)
                    .textInputAutocapitalization(.words)
            } header: {
                Text(parentTag != nil ? "Child of \"\(parentTag!.name)\"" : "New Tag")
            }

            Section("Color") {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 8), spacing: 12) {
                    ForEach(presetColors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().stroke(.white, lineWidth: colorHex == hex ? 3 : 0)
                                    .padding(2)
                            )
                            .shadow(radius: colorHex == hex ? 4 : 0)
                            .onTapGesture { colorHex = hex }
                    }
                }
                .padding(.vertical, 4)

                ColorPicker("Custom Color", selection: $customColor, supportsOpacity: false)
                    .onChange(of: customColor) { _, newColor in
                        colorHex = newColor.hexString
                    }
            }

            Section("Icon") {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: 12) {
                    ForEach(presetSymbols, id: \.self) { sym in
                        Image(systemName: sym)
                            .font(.system(size: 22))
                            .foregroundStyle(sym == symbol ? Color(hex: colorHex) : AppTheme.Colors.secondaryLabel)
                            .frame(width: 44, height: 44)
                            .background(sym == symbol ? Color(hex: colorHex).opacity(0.12) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .onTapGesture { symbol = sym }
                    }
                }
                .padding(.vertical, 4)

                Button {
                    withAnimation { showEmojis.toggle() }
                } label: {
                    HStack {
                        Text(showEmojis ? "Hide Emojis" : "More (Emojis)")
                            .foregroundStyle(AppTheme.Colors.accent)
                        Spacer()
                        Image(systemName: showEmojis ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    }
                }

                if showEmojis {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 8), spacing: 12) {
                        ForEach(presetEmojis, id: \.self) { emoji in
                            Text(emoji)
                                .font(.system(size: 24))
                                .frame(width: 40, height: 40)
                                .background(emoji == symbol ? Color(hex: colorHex).opacity(0.15) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(emoji == symbol ? Color(hex: colorHex) : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture { symbol = emoji }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Preview") {
                TagChipView(tag: previewTag)
            }
        }
        .navigationTitle("New Tag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    guard !name.isEmpty else { return }
                    onCreate(name, colorHex, symbol)
                }
                .disabled(name.isEmpty)
            }
        }
    }

    private var previewTag: Tag {
        Tag(name: name.isEmpty ? "Preview" : name, colorHex: colorHex, sfSymbol: symbol)
    }
}
