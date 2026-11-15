import SwiftUI
import SwiftData

struct KnowledgeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var viewModel = KnowledgeViewModel()
    @State private var navigationPath: [Tag] = []
    @State private var activeSheet: TagSheet?
    @State private var tagPendingDeletion: Tag?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    hierarchyHeader

                    if shouldOfferCreateFromSearch {
                        createFromSearchButton
                    }

                    hierarchyContent
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.Spacing.base)
                .padding(.bottom, 120)
            }
            .background(AppTheme.Colors.groupedBG)
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: searchBinding,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Find a tag"
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .create(parent: nil, initialName: "")
                    } label: {
                        Label("New Tag", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            .navigationDestination(for: Tag.self) { tag in
                TagDetailView(
                    tag: tag,
                    viewModel: viewModel,
                    onEdit: { activeSheet = .edit(tag) }
                )
            }
            .onAppear { viewModel.setup(context: modelContext) }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
                .errorAlert(message: errorBinding)
        }
        .deleteTagAlert(tag: $tagPendingDeletion) { tag in
            if !viewModel.deleteTagPromotingChildren(tag) {
                // The observable error alert is presented after this confirmation closes.
            }
        }
        .errorAlert(message: errorBinding)
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { viewModel.searchText },
            set: { viewModel.setSearchText($0) }
        )
    }

    private var errorBinding: Binding<String?> {
        Binding(
            get: { viewModel.errorMessage },
            set: { if $0 == nil { viewModel.clearError() } }
        )
    }

    private var isSearching: Bool { !viewModel.trimmedSearchText.isEmpty }

    private var shouldOfferCreateFromSearch: Bool {
        isSearching && !viewModel.hasExactSearchMatch
    }

    private var hierarchyHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    hierarchyTitle
                    if showsExpansionControl { expansionButton }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    hierarchyTitle
                    Spacer()
                    if showsExpansionControl { expansionButton }
                }
            }
        }
        .padding(.top, AppTheme.Spacing.small)
    }

    private var hierarchyTitle: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
            Text(isSearching ? "Search Results" : "All Tags")
                .font(AppTheme.Typography.title3)
                .foregroundStyle(AppTheme.Colors.label)

            Text(headerCountText)
                .font(AppTheme.Typography.caption1)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
        }
    }

    private var showsExpansionControl: Bool {
        !viewModel.allTags.isEmpty && !isSearching
    }

    private var expansionButton: some View {
        Button(viewModel.areAllBranchesExpanded ? "Collapse All" : "Expand All") {
            if reduceMotion {
                toggleAllBranches()
            } else {
                withAnimation(AppTheme.Animation.snappy) {
                    toggleAllBranches()
                }
            }
        }
        .font(AppTheme.Typography.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var hierarchyContent: some View {
        if viewModel.allTags.isEmpty && !isSearching {
            ContentUnavailableView {
                Label("No Tags Yet", systemImage: "tag")
            } description: {
                Text("Create a tag to organize related files and build your hierarchy.")
            } actions: {
                Button("Create Tag") {
                    activeSheet = .create(parent: nil, initialName: "")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if viewModel.filteredRootTags.isEmpty {
            ContentUnavailableView.search(text: viewModel.trimmedSearchText)
                .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredRootTags) { tag in
                    hierarchyNode(tag, depth: 0)
                    if tag.id != viewModel.filteredRootTags.last?.id { Divider() }
                }
            }
            .background(AppTheme.Colors.flatCard)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .strokeBorder(AppTheme.Colors.separator.opacity(0.25), lineWidth: 0.5)
            }
        }
    }

    private var createFromSearchButton: some View {
        Button {
            activeSheet = .create(parent: nil, initialName: viewModel.trimmedSearchText)
        } label: {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.Colors.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                    Text("Create “\(viewModel.trimmedSearchText)”")
                        .font(AppTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.label)
                    Text("Choose its appearance and place in the hierarchy")
                        .font(AppTheme.Typography.caption1)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }

                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    .accessibilityHidden(true)
            }
            .padding(AppTheme.Spacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.secondaryBG)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the tag editor with this name filled in")
    }

    private func hierarchyNode(_ tag: Tag, depth: Int) -> some View {
        TagNodeView(
            tag: tag,
            depth: depth,
            visibleChildren: viewModel.visibleChildren,
            expandedIDs: $viewModel.expandedTagIDs,
            onSelect: { navigationPath.append($0) },
            onCreateChild: { activeSheet = .create(parent: $0, initialName: "") },
            onMove: { activeSheet = .move($0) },
            onEdit: { activeSheet = .edit($0) },
            onDelete: { tagPendingDeletion = $0 }
        )
    }

    private var headerCountText: String {
        if isSearching {
            let count = viewModel.matchingTagIDs.count
            return "\(count) matching tag\(count == 1 ? "" : "s")"
        }
        let count = viewModel.allTags.count
        return "\(count) tag\(count == 1 ? "" : "s")"
    }

    private func toggleAllBranches() {
        if viewModel.areAllBranchesExpanded {
            viewModel.collapseAll()
        } else {
            viewModel.expandAll()
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: TagSheet) -> some View {
        switch sheet {
        case let .create(parent, initialName):
            NavigationStack {
                TagEditorView(
                    initialName: initialName,
                    initialParent: parent,
                    availableParents: viewModel.availableParents(for: nil)
                ) { name, color, symbol, selectedParent in
                    let saved = viewModel.createTag(
                        name: name,
                        colorHex: color,
                        sfSymbol: symbol,
                        parent: selectedParent
                    )
                    if saved { viewModel.setSearchText("") }
                    return saved
                }
            }

        case let .edit(tag):
            NavigationStack {
                TagEditorView(
                    editingTag: tag,
                    initialParent: viewModel.parent(of: tag),
                    availableParents: viewModel.availableParents(for: tag)
                ) { name, color, symbol, selectedParent in
                    viewModel.updateTag(
                        tag,
                        name: name,
                        colorHex: color,
                        sfSymbol: symbol,
                        parent: selectedParent
                    )
                }
            }

        case let .move(tag):
            NavigationStack {
                MoveTagView(
                    tag: tag,
                    currentParent: viewModel.parent(of: tag),
                    candidates: viewModel.availableParents(for: tag),
                    onMove: { viewModel.moveTag(tag, to: $0) }
                )
            }
        }
    }
}

// MARK: - Presentation state

private enum TagSheet: Identifiable {
    case create(parent: Tag?, initialName: String)
    case edit(Tag)
    case move(Tag)

    var id: String {
        switch self {
        case let .create(parent, _): "create-\(parent?.id.uuidString ?? "root")"
        case let .edit(tag): "edit-\(tag.id.uuidString)"
        case let .move(tag): "move-\(tag.id.uuidString)"
        }
    }
}

// MARK: - Tag detail

private struct TagDetailView: View {
    let tag: Tag
    @Bindable var viewModel: KnowledgeViewModel
    var onEdit: () -> Void

    @Environment(FileViewerCoordinator.self) private var fileViewer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
                detailHeader
                filesSection
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.base)
            .padding(.bottom, AppTheme.Spacing.xxxLarge)
        }
        .background(AppTheme.Colors.groupedBG)
        .navigationTitle("Tag Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: onEdit)
            }
        }
        .onAppear { viewModel.loadItems(for: tag) }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            identity
                .padding(AppTheme.Spacing.base)

            if !tag.children.isEmpty {
                Divider()

                Label("Includes files from nested subtags.", systemImage: "square.stack.3d.up")
                    .font(AppTheme.Typography.footnote)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.base)
                    .padding(.vertical, AppTheme.Spacing.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(scopeBackground)
            }
        }
        .background(AppTheme.Colors.flatCard)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                .strokeBorder(
                    AppTheme.Colors.separator.opacity(colorSchemeContrast == .increased ? 0.75 : 0.28),
                    lineWidth: colorSchemeContrast == .increased ? 1 : 0.5
                )
        }
    }

    @ViewBuilder
    private var identity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.base) {
                tagIcon
                identityText
                metrics
            }
        } else {
            HStack(alignment: .center, spacing: AppTheme.Spacing.medium) {
                tagIcon
                identityText
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                metrics
            }
        }
    }

    private var tagIcon: some View {
        TagSymbolView(
            sfSymbol: tag.sfSymbol,
            color: tagColor,
            size: 22
        )
        .frame(width: 48, height: 48)
        .background(reduceTransparency ? AppTheme.Colors.tertiaryBG : tagColor.opacity(AppTheme.Tint.wash))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .accessibilityHidden(true)
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text(tag.name)
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.label)
                .fixedSize(horizontal: false, vertical: true)

            Label {
                Text(breadcrumb)
                    .lineLimit(2)
            } icon: {
                Image(systemName: "folder")
                    .accessibilityHidden(true)
            }
            .font(AppTheme.Typography.subheadline)
            .foregroundStyle(AppTheme.Colors.secondaryLabel)
            .accessibilityLabel("Location: \(breadcrumb)")
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            TagMetric(
                value: tag.children.count,
                label: tag.children.count == 1 ? "Subtag" : "Subtags",
                symbol: "tag",
                tint: tagColor,
                reduceTransparency: reduceTransparency
            )

            TagMetric(
                value: viewModel.tagItems.count,
                label: "Files",
                symbol: "doc",
                tint: tagColor,
                reduceTransparency: reduceTransparency
            )
        }
    }

    private var tagColor: Color {
        Color(hex: tag.colorHex)
    }

    private var scopeBackground: Color {
        reduceTransparency ? AppTheme.Colors.tertiaryBG : tagColor.opacity(0.055)
    }

    @ViewBuilder
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Files")
                .font(AppTheme.Typography.title3)

            if viewModel.tagItems.isEmpty {
                ContentUnavailableView {
                    Label("No Files", systemImage: "tray")
                } description: {
                    Text(tag.children.isEmpty
                         ? "No files use this tag yet."
                         : "No files use this tag or its subtags yet.")
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVStack(spacing: AppTheme.Spacing.medium) {
                    ForEach(viewModel.tagItems) { item in
                        Button { fileViewer.open(item) } label: {
                            ItemCardView(item: item, style: .row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var breadcrumb: String {
        let names = viewModel.path(to: tag).dropLast().map(\.name)
        return names.isEmpty ? "Top-level tag" : names.joined(separator: "  ›  ")
    }
}

private struct TagMetric: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color
    let reduceTransparency: Bool

    @ScaledMetric(relativeTo: .subheadline) private var iconContainerSize: CGFloat = 28

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: resolvedGlyphSize, height: resolvedGlyphSize)
                .foregroundStyle(tint)
                .frame(width: resolvedIconSize, height: resolvedIconSize)
                .background(reduceTransparency ? AppTheme.Colors.tertiaryBG : tint.opacity(AppTheme.Tint.wash))
                .clipShape(Circle())
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xSmall) {
                Text(value, format: .number)
                    .font(AppTheme.Typography.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.label)
                Text(label)
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var resolvedIconSize: CGFloat {
        min(iconContainerSize, 38)
    }

    private var resolvedGlyphSize: CGFloat {
        resolvedIconSize * 0.48
    }
}

// MARK: - Move tag

private struct MoveTagView: View {
    let tag: Tag
    let currentParent: Tag?
    let candidates: [Tag]
    var onMove: (Tag?) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                destinationButton(title: "Top Level", symbol: "square.stack.3d.up", parent: nil)
            } footer: {
                Text("Moving a tag changes its parent. Its files and subtags stay with it.")
            }

            Section("Move under") {
                ForEach(filteredCandidates) { candidate in
                    destinationButton(
                        title: candidate.name,
                        symbol: candidate.sfSymbol,
                        color: Color(hex: candidate.colorHex),
                        parent: candidate
                    )
                }
            }
        }
        .navigationTitle("Move \(tag.name)")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Find a parent tag")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var filteredCandidates: [Tag] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.name.localizedStandardContains(query) }
    }

    private func destinationButton(
        title: String,
        symbol: String,
        color: Color = AppTheme.Colors.secondaryLabel,
        parent: Tag?
    ) -> some View {
        Button {
            if onMove(parent) { dismiss() }
        } label: {
            HStack(spacing: AppTheme.Spacing.medium) {
                TagSymbolView(sfSymbol: symbol, color: color, size: 16)
                    .frame(width: 30, height: 30)
                Text(title)
                    .foregroundStyle(AppTheme.Colors.label)
                Spacer()
                if currentParent?.id == parent?.id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .accessibilityLabel("Current parent")
                }
            }
        }
        .disabled(currentParent?.id == parent?.id)
    }
}

// MARK: - Tag editor

private struct TagEditorView: View {
    var editingTag: Tag?
    let availableParents: [Tag]
    var onSave: (String, String, String, Tag?) -> Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    @State private var name: String
    @State private var colorHex: String
    @State private var symbol: String
    @State private var parent: Tag?
    @State private var customColor: Color
    @State private var showEmojis = false
    @State private var iconSearchText = ""
    @State private var selectedIconCategory: TagIconPickerCategory = .recent
    @State private var showsAllIcons = false
    @AppStorage("recentTagIcons") private var recentIconStorage = ""

    init(
        editingTag: Tag? = nil,
        initialName: String = "",
        initialParent: Tag?,
        availableParents: [Tag],
        onSave: @escaping (String, String, String, Tag?) -> Bool
    ) {
        self.editingTag = editingTag
        self.availableParents = availableParents
        self.onSave = onSave

        let startingColor = editingTag?.colorHex ?? "#1F90E4"
        _name = State(initialValue: editingTag?.name ?? initialName)
        _colorHex = State(initialValue: startingColor)
        _symbol = State(initialValue: editingTag?.sfSymbol ?? "tag.fill")
        _parent = State(initialValue: initialParent)
        _customColor = State(initialValue: Color(hex: startingColor))
    }

    private let colors: [(name: String, hex: String)] = [
        ("Blue", "#1F90E4"), ("Green", "#2ECC71"), ("Red", "#E74C3C"),
        ("Purple", "#9B59B6"), ("Orange", "#F39C12"), ("Pink", "#E84393")
    ]

    private let emojis = [
        "📁", "📄", "📝", "📌", "🔖", "💼", "📊", "💡", "🎯", "⚙️",
        "🎨", "📷", "🎵", "🎬", "🏆", "🚀", "🌟", "🌿", "🔥", "☕"
    ]

    var body: some View {
        Form {
            Section("Name") {
                TextField("Tag name", text: $name)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }

            Section("Hierarchy") {
                NavigationLink {
                    ParentPickerView(candidates: availableParents, selection: $parent)
                } label: {
                    LabeledContent("Parent") {
                        Text(parent?.name ?? "Top Level")
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }
                }
            }

            Section("Color") {
                ScrollView(.horizontal) {
                    HStack(spacing: AppTheme.Spacing.medium) {
                        ForEach(colors, id: \.hex) { option in
                            Button {
                                colorHex = option.hex
                                customColor = Color(hex: option.hex)
                            } label: {
                                Circle()
                                    .fill(Color(hex: option.hex))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if colorHex == option.hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(option.name) color")
                            .accessibilityAddTraits(colorHex == option.hex ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)

                ColorPicker("Custom Color", selection: $customColor, supportsOpacity: false)
                    .onChange(of: customColor) { _, newValue in
                        colorHex = newValue.hexString
                    }
            }

            Section("Icon") {
                iconSearchField

                if trimmedIconSearch.isEmpty {
                    categoryPicker
                } else {
                    Text("Searching all categories")
                        .font(AppTheme.Typography.caption1)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }

                if trimmedIconSearch.isEmpty, selectedIconCategory == .recent {
                    if recentIconValues.isEmpty {
                        ContentUnavailableView(
                            "No Recent Icons",
                            systemImage: "clock",
                            description: Text("Icons you choose will appear here.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 140)
                    } else {
                        recentIconGrid
                    }
                } else if filteredIconOptions.isEmpty {
                    ContentUnavailableView.search(text: trimmedIconSearch)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else if showsAllIconsControl {
                    allIconsGrid
                } else {
                    iconGrid(filteredIconOptions)
                }

                DisclosureGroup("Emoji Icons", isExpanded: $showEmojis) {
                    emojiGrid
                        .padding(.top, AppTheme.Spacing.small)
                }
            }

            Section("Preview") {
                HStack(spacing: AppTheme.Spacing.medium) {
                    TagSymbolView(sfSymbol: symbol, color: Color(hex: colorHex), size: 18)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: colorHex).opacity(AppTheme.Tint.wash))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                    Text(trimmedName.isEmpty ? "Tag name" : trimmedName)
                        .font(AppTheme.Typography.body.weight(.medium))
                        .foregroundStyle(trimmedName.isEmpty
                                         ? AppTheme.Colors.secondaryLabel
                                         : AppTheme.Colors.label)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Preview: \(trimmedName.isEmpty ? "Tag name" : trimmedName)")
            }
        }
        .navigationTitle(editingTag == nil ? "New Tag" : "Edit Tag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if onSave(trimmedName, colorHex, symbol, parent) { dismiss() }
                }
                .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear {
            if editingTag == nil { nameFocused = true }
            recordRecentIcon(symbol)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedIconSearch: String {
        iconSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredIconOptions: [TagIconOption] {
        let query = trimmedIconSearch
        if !query.isEmpty {
            return TagIconCatalog.search(query)
        }

        if selectedIconCategory == .all {
            return TagIconCatalog.options
        }

        guard let catalogCategory = selectedIconCategory.catalogCategory else { return [] }
        return TagIconCatalog.options(in: catalogCategory)
    }

    private var showsAllIconsControl: Bool {
        trimmedIconSearch.isEmpty && selectedIconCategory == .all
    }

    private var iconSearchField: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                .accessibilityHidden(true)

            TextField("Search icons", text: $iconSearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !iconSearchText.isEmpty {
                Button("Clear") { iconSearchText = "" }
                    .font(AppTheme.Typography.subheadline)
            }
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(TagIconPickerCategory.allCases) { category in
                    Button {
                        selectedIconCategory = category
                    } label: {
                        Text(category.rawValue)
                            .font(AppTheme.Typography.subheadline.weight(.medium))
                            .foregroundStyle(
                                selectedIconCategory == category
                                    ? Color.white
                                    : AppTheme.Colors.label
                            )
                            .padding(.horizontal, AppTheme.Spacing.medium)
                            .frame(minHeight: 36)
                            .background(
                                selectedIconCategory == category
                                    ? AppTheme.Colors.accent
                                    : AppTheme.Colors.secondaryFill
                            )
                            .clipShape(Capsule())
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedIconCategory == category ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var allIconsGrid: some View {
        ViewThatFits(in: .horizontal) {
            allIconsGrid(columnCount: 6)
            allIconsGrid(columnCount: 5)
            allIconsGrid(columnCount: 4)
        }
    }

    private func allIconsGrid(columnCount: Int) -> some View {
        let previewCount = columnCount * 2 - 1
        let previewOptions = Array(TagIconCatalog.options.prefix(previewCount))
        let remainingOptions = Array(TagIconCatalog.options.dropFirst(previewCount))

        return iconGridContainer(columnCount: columnCount) {
            ForEach(previewOptions, id: \.self) { option in
                iconButton(value: option.systemName, accessibilityName: option.name)
            }

            Button {
                showsAllIcons.toggle()
            } label: {
                HStack(spacing: AppTheme.Spacing.xxSmall) {
                    Text(showsAllIcons ? "Less" : "+\(remainingOptions.count)")
                        .font(AppTheme.Typography.caption1.weight(.semibold))
                    Image(systemName: showsAllIcons ? "chevron.up" : "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.Colors.secondaryFill)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                showsAllIcons
                    ? "Show fewer icons"
                    : "Show \(remainingOptions.count) more icons"
            )
            .accessibilityHint(showsAllIcons ? "Collapses the additional icons" : "Expands the remaining icons")

            if showsAllIcons {
                ForEach(remainingOptions, id: \.self) { option in
                    iconButton(value: option.systemName, accessibilityName: option.name)
                }
            }
        }
    }

    private func iconGrid(_ options: [TagIconOption]) -> some View {
        responsiveIconGrid {
            ForEach(options, id: \.self) { option in
                iconButton(value: option.systemName, accessibilityName: option.name)
            }
        }
    }

    private var recentIconGrid: some View {
        responsiveIconGrid {
            ForEach(recentIconValues, id: \.self) { value in
                iconButton(value: value, accessibilityName: accessibleName(for: value))
            }
        }
    }

    private var emojiGrid: some View {
        responsiveIconGrid {
            ForEach(emojis, id: \.self) { emoji in
                iconButton(value: emoji, accessibilityName: "\(emoji) emoji")
            }
        }
    }

    private func responsiveIconGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            iconGridContainer(columnCount: 6, content: content)
            iconGridContainer(columnCount: 5, content: content)
            iconGridContainer(columnCount: 4, content: content)
        }
    }

    private func iconGridContainer<Content: View>(
        columnCount: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 44), spacing: AppTheme.Spacing.small),
            count: columnCount
        )
        let minimumWidth = CGFloat(columnCount * 44)
            + CGFloat(columnCount - 1) * AppTheme.Spacing.small

        return LazyVGrid(columns: columns, spacing: AppTheme.Spacing.small) {
            content()
        }
        .frame(minWidth: minimumWidth, maxWidth: .infinity)
    }

    private func iconButton(value: String, accessibilityName: String) -> some View {
        Button {
            symbol = value
            recordRecentIcon(value)
        } label: {
            TagSymbolView(
                sfSymbol: value,
                color: symbol == value ? Color(hex: colorHex) : AppTheme.Colors.secondaryLabel,
                size: value.unicodeScalars.allSatisfy { $0.value < 128 } ? 20 : 22
            )
            .frame(width: 44, height: 44)
            .background(symbol == value ? Color(hex: colorHex).opacity(AppTheme.Tint.wash) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if symbol == value {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hex: colorHex))
                        .background(Circle().fill(AppTheme.Colors.background))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityName) icon")
        .accessibilityAddTraits(symbol == value ? .isSelected : [])
    }

    private var recentIconValues: [String] {
        recentIconStorage
            .split(separator: "\n")
            .map(String.init)
    }

    private func recordRecentIcon(_ value: String) {
        guard !value.isEmpty else { return }
        let updated = [value] + recentIconValues.filter { $0 != value }
        recentIconStorage = updated.prefix(8).joined(separator: "\n")
    }

    private func accessibleName(for value: String) -> String {
        if let option = TagIconCatalog.options.first(where: { $0.systemName == value }) {
            return option.name
        }
        if emojis.contains(value) { return "\(value) emoji" }
        return value.replacingOccurrences(of: ".", with: " ")
    }
}

private enum TagIconPickerCategory: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case all = "All"
    case general = "General"
    case documents = "Documents"
    case work = "Work"
    case personal = "Personal"
    case media = "Media"
    case travel = "Travel"
    case finance = "Finance"
    case nature = "Nature"

    var id: Self { self }

    var catalogCategory: TagIconCategory? {
        TagIconCategory(rawValue: rawValue)
    }
}

enum TagIconCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case documents = "Documents"
    case work = "Work"
    case personal = "Personal"
    case media = "Media"
    case travel = "Travel"
    case finance = "Finance"
    case nature = "Nature"

    var id: Self { self }
}

struct TagIconOption: Hashable {
    let systemName: String
    let name: String
    let category: TagIconCategory
}

enum TagIconCatalog {
    static let options: [TagIconOption] = [
        // General
        .init(systemName: "tag.fill", name: "Tag", category: .general),
        .init(systemName: "folder.fill", name: "Folder", category: .general),
        .init(systemName: "star.fill", name: "Star", category: .general),
        .init(systemName: "heart.fill", name: "Heart", category: .general),
        .init(systemName: "house.fill", name: "Home", category: .general),
        .init(systemName: "bookmark.fill", name: "Bookmark", category: .general),
        .init(systemName: "flag.fill", name: "Flag", category: .general),
        .init(systemName: "pin.fill", name: "Pin", category: .general),
        .init(systemName: "bell.fill", name: "Bell", category: .general),
        .init(systemName: "bolt.fill", name: "Bolt", category: .general),
        .init(systemName: "checkmark.circle.fill", name: "Completed", category: .general),
        .init(systemName: "lightbulb.fill", name: "Idea", category: .general),

        // Documents
        .init(systemName: "doc.fill", name: "Document", category: .documents),
        .init(systemName: "doc.text.fill", name: "Text Document", category: .documents),
        .init(systemName: "doc.richtext.fill", name: "Rich Text", category: .documents),
        .init(systemName: "doc.on.doc.fill", name: "Documents", category: .documents),
        .init(systemName: "note.text", name: "Note", category: .documents),
        .init(systemName: "list.bullet.rectangle.fill", name: "List", category: .documents),
        .init(systemName: "book.fill", name: "Book", category: .documents),
        .init(systemName: "books.vertical.fill", name: "Library", category: .documents),
        .init(systemName: "newspaper.fill", name: "News", category: .documents),
        .init(systemName: "tray.full.fill", name: "Inbox", category: .documents),
        .init(systemName: "archivebox.fill", name: "Archive", category: .documents),
        .init(systemName: "paperclip", name: "Attachment", category: .documents),

        // Work
        .init(systemName: "briefcase.fill", name: "Briefcase", category: .work),
        .init(systemName: "building.2.fill", name: "Office", category: .work),
        .init(systemName: "person.2.fill", name: "Team", category: .work),
        .init(systemName: "calendar", name: "Calendar", category: .work),
        .init(systemName: "clock.fill", name: "Time", category: .work),
        .init(systemName: "chart.bar.fill", name: "Bar Chart", category: .work),
        .init(systemName: "chart.line.uptrend.xyaxis", name: "Growth", category: .work),
        .init(systemName: "rectangle.3.group.fill", name: "Project", category: .work),
        .init(systemName: "checklist", name: "Checklist", category: .work),
        .init(systemName: "hammer.fill", name: "Build", category: .work),
        .init(systemName: "wrench.adjustable.fill", name: "Tools", category: .work),
        .init(systemName: "shippingbox.fill", name: "Package", category: .work),

        // Personal
        .init(systemName: "person.fill", name: "Person", category: .personal),
        .init(systemName: "figure.walk", name: "Walking", category: .personal),
        .init(systemName: "dumbbell.fill", name: "Fitness", category: .personal),
        .init(systemName: "cross.case.fill", name: "Health", category: .personal),
        .init(systemName: "birthday.cake.fill", name: "Birthday", category: .personal),
        .init(systemName: "cart.fill", name: "Shopping", category: .personal),
        .init(systemName: "gift.fill", name: "Gift", category: .personal),
        .init(systemName: "key.fill", name: "Key", category: .personal),
        .init(systemName: "lock.fill", name: "Private", category: .personal),
        .init(systemName: "graduationcap.fill", name: "Education", category: .personal),
        .init(systemName: "pawprint.fill", name: "Pets", category: .personal),
        .init(systemName: "tshirt.fill", name: "Clothing", category: .personal),

        // Media
        .init(systemName: "camera.fill", name: "Camera", category: .media),
        .init(systemName: "photo.fill", name: "Photo", category: .media),
        .init(systemName: "video.fill", name: "Video", category: .media),
        .init(systemName: "film.fill", name: "Film", category: .media),
        .init(systemName: "music.note", name: "Music", category: .media),
        .init(systemName: "headphones", name: "Headphones", category: .media),
        .init(systemName: "mic.fill", name: "Microphone", category: .media),
        .init(systemName: "speaker.wave.2.fill", name: "Audio", category: .media),
        .init(systemName: "play.rectangle.fill", name: "Playback", category: .media),
        .init(systemName: "gamecontroller.fill", name: "Games", category: .media),
        .init(systemName: "paintbrush.fill", name: "Art", category: .media),
        .init(systemName: "pencil.and.outline", name: "Drawing", category: .media),

        // Travel
        .init(systemName: "airplane", name: "Airplane", category: .travel),
        .init(systemName: "car.fill", name: "Car", category: .travel),
        .init(systemName: "bus.fill", name: "Bus", category: .travel),
        .init(systemName: "tram.fill", name: "Train", category: .travel),
        .init(systemName: "bicycle", name: "Bicycle", category: .travel),
        .init(systemName: "sailboat.fill", name: "Boat", category: .travel),
        .init(systemName: "map.fill", name: "Map", category: .travel),
        .init(systemName: "mappin.and.ellipse", name: "Location", category: .travel),
        .init(systemName: "suitcase.fill", name: "Luggage", category: .travel),
        .init(systemName: "tent.fill", name: "Camping", category: .travel),
        .init(systemName: "fuelpump.fill", name: "Fuel", category: .travel),
        .init(systemName: "globe.americas.fill", name: "World", category: .travel),

        // Finance
        .init(systemName: "dollarsign.circle.fill", name: "Dollar", category: .finance),
        .init(systemName: "creditcard.fill", name: "Credit Card", category: .finance),
        .init(systemName: "banknote.fill", name: "Cash", category: .finance),
        .init(systemName: "wallet.pass.fill", name: "Wallet", category: .finance),
        .init(systemName: "chart.pie.fill", name: "Pie Chart", category: .finance),
        .init(systemName: "percent", name: "Percentage", category: .finance),
        .init(systemName: "receipt.fill", name: "Receipt", category: .finance),
        .init(systemName: "building.columns.fill", name: "Bank", category: .finance),
        .init(systemName: "bitcoinsign.circle.fill", name: "Bitcoin", category: .finance),
        .init(systemName: "eurosign.circle.fill", name: "Euro", category: .finance),
        .init(systemName: "indianrupeesign.circle.fill", name: "Indian Rupee", category: .finance),
        .init(systemName: "yensign.circle.fill", name: "Yen", category: .finance),

        // Nature
        .init(systemName: "leaf.fill", name: "Leaf", category: .nature),
        .init(systemName: "tree.fill", name: "Tree", category: .nature),
        .init(systemName: "camera.macro", name: "Flower", category: .nature),
        .init(systemName: "sun.max.fill", name: "Sun", category: .nature),
        .init(systemName: "moon.fill", name: "Moon", category: .nature),
        .init(systemName: "cloud.fill", name: "Cloud", category: .nature),
        .init(systemName: "drop.fill", name: "Water", category: .nature),
        .init(systemName: "flame.fill", name: "Fire", category: .nature),
        .init(systemName: "snowflake", name: "Snow", category: .nature),
        .init(systemName: "mountain.2.fill", name: "Mountains", category: .nature),
        .init(systemName: "ladybug.fill", name: "Insect", category: .nature),
        .init(systemName: "fish.fill", name: "Fish", category: .nature)
    ]

    static func options(in category: TagIconCategory) -> [TagIconOption] {
        options.filter { $0.category == category }
    }

    static func search(_ query: String) -> [TagIconOption] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return options }

        return options.filter {
            $0.name.localizedStandardContains(normalized)
                || $0.systemName.localizedStandardContains(normalized)
                || $0.category.rawValue.localizedStandardContains(normalized)
        }
    }
}

private struct ParentPickerView: View {
    let candidates: [Tag]
    @Binding var selection: Tag?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        List {
            Button {
                selection = nil
                dismiss()
            } label: {
                parentRow(title: "Top Level", symbol: "square.stack.3d.up", isSelected: selection == nil)
            }

            ForEach(filteredCandidates) { candidate in
                Button {
                    selection = candidate
                    dismiss()
                } label: {
                    parentRow(
                        title: candidate.name,
                        symbol: candidate.sfSymbol,
                        color: Color(hex: candidate.colorHex),
                        isSelected: selection?.id == candidate.id
                    )
                }
            }
        }
        .navigationTitle("Choose Parent")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Find a parent tag")
    }

    private var filteredCandidates: [Tag] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.name.localizedStandardContains(query) }
    }

    private func parentRow(
        title: String,
        symbol: String,
        color: Color = AppTheme.Colors.secondaryLabel,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            TagSymbolView(sfSymbol: symbol, color: color, size: 16)
                .frame(width: 30, height: 30)
            Text(title)
                .foregroundStyle(AppTheme.Colors.label)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .accessibilityLabel("Selected")
            }
        }
    }
}

// MARK: - Alerts

private extension View {
    func errorAlert(message: Binding<String?>) -> some View {
        alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "Please try again.")
        }
    }

    func deleteTagAlert(tag: Binding<Tag?>, onDelete: @escaping (Tag) -> Void) -> some View {
        alert(
            tag.wrappedValue.map { "Delete “\($0.name)”?" } ?? "Delete Tag?",
            isPresented: Binding(
                get: { tag.wrappedValue != nil },
                set: { if !$0 { tag.wrappedValue = nil } }
            ),
            presenting: tag.wrappedValue
        ) { selectedTag in
            Button("Delete", role: .destructive) {
                onDelete(selectedTag)
                tag.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) {
                tag.wrappedValue = nil
            }
        } message: { selectedTag in
            if selectedTag.children.isEmpty {
                Text("The tag will be removed. Its files will be kept.")
            } else {
                Text("The tag will be removed, its files will be kept, and its \(selectedTag.children.count) subtag\(selectedTag.children.count == 1 ? "" : "s") will move up one level.")
            }
        }
    }
}

// MARK: - Preview fixtures

@MainActor
private func makeTagsPreviewContainer() -> ModelContainer {
    let container = PersistenceController(inMemory: true).container
    let context = container.mainContext

    let work = Tag(name: "Work", colorHex: "#1F90E4", sfSymbol: "briefcase.fill")
    let projects = Tag(name: "Projects", colorHex: "#9B59B6", sfSymbol: "folder.fill")
    let reports = Tag(name: "Quarterly Reports", colorHex: "#E74C3C", sfSymbol: "doc.fill")
    let personal = Tag(name: "Personal", colorHex: "#2ECC71", sfSymbol: "person.fill")
    work.children.append(projects)
    projects.children.append(reports)

    context.insert(work)
    context.insert(projects)
    context.insert(reports)
    context.insert(personal)
    try? context.save()
    return container
}

#Preview("Tags — Standard") {
    KnowledgeView()
        .modelContainer(makeTagsPreviewContainer())
        .environment(FileViewerCoordinator())
}

#Preview("Tags — Accessibility Dark") {
    KnowledgeView()
        .modelContainer(makeTagsPreviewContainer())
        .environment(FileViewerCoordinator())
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}
