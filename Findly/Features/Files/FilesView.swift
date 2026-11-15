import SwiftUI
import SwiftData

struct FilesView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @Environment(FileViewerCoordinator.self) private var fileViewer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel = FilesViewModel()
    @State private var showFilterSheet = false
    @State private var showBulkTagPicker = false
    @State private var scrollOffset: CGFloat = 0

    private var titleProgress: CGFloat {
        viewModel.isSelectMode ? 1.0 : scrollProgress(from: scrollOffset)
    }

    private var inlineTitle: String {
        viewModel.isSelectMode ? "\(viewModel.selectedIDs.count) Selected" : "Files"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        LargeTitleHeader(title: "Files", progress: scrollProgress(from: scrollOffset))
                        refinementBar
                        filesContent
                    }
                }
                .background(AppTheme.Colors.groupedBG)
                .trackScrollOffset($scrollOffset)

                if viewModel.isSelectMode {
                    BulkActionsBar(
                        selectedCount: viewModel.selectedIDs.count,
                        onTag: { showBulkTagPicker = true },
                        onFavorite: { viewModel.bulkFavorite() },
                        onDelete: { viewModel.bulkDelete(localStorage: appContainer.localStorage) },
                        onCancel: { viewModel.exitSelectMode() }
                    )
                }
            }
            .navTransitionTitle(inlineTitle, progress: titleProgress)
            .toolbar { filesToolbar }
            .sheet(isPresented: $showFilterSheet) {
                FilesFilterSheetView(
                    selectedFileTypes: viewModel.selectedFileTypes,
                    sortOrder: viewModel.sortOrder,
                    filterDateStart: viewModel.filterDateStart,
                    filterDateEnd: viewModel.filterDateEnd
                ) { types, sort, start, end in
                    viewModel.applyRefinements(
                        fileTypes: types,
                        sortOrder: sort,
                        dateStart: start,
                        dateEnd: end
                    )
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showBulkTagPicker) {
                BulkTagPickerSheet { tag in
                    viewModel.bulkTag(tag)
                }
            }
            .onAppear {
                viewModel.setup(context: modelContext)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var filesToolbar: some ToolbarContent {
        if viewModel.isSelectMode {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { viewModel.exitSelectMode() }
                    .foregroundStyle(AppTheme.Colors.accent)
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { viewModel.toggleLayout() } label: {
                    Image(systemName: viewModel.layoutStyle == .list
                          ? "square.grid.2x2"
                          : "list.bullet")
                }
                .accessibilityLabel(viewModel.layoutStyle == .list ? "Show grid" : "Show list")

                Button { viewModel.enterSelectMode() } label: {
                    Image(systemName: "checkmark.circle")
                }
                .accessibilityLabel("Select files")
            }
        }
    }

    // MARK: - Refinement controls

    private var refinementBar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.small) {
                    librarySummary
                    Spacer(minLength: AppTheme.Spacing.small)
                    refinementControls
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    librarySummary
                    refinementControls
                }
            }

            if viewModel.hasActiveFilters {
                activeFilterChips
            }
        }
        .padding(.horizontal, AppTheme.Spacing.base)
        .padding(.bottom, AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var librarySummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
            Text(viewModel.hasActiveFilters ? "Filtered library" : "Your library")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.label)
            Text(viewModel.itemCountSummary)
                .font(AppTheme.Typography.caption1)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
        }
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }

    @ViewBuilder
    private var refinementControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                sortControl
                filterControl
            }
        } else {
            HStack(spacing: AppTheme.Spacing.small) {
                sortControl
                filterControl
            }
        }
    }

    private var sortControl: some View {
        FilesSortMenu(
            selection: Binding(
                get: { viewModel.sortOrder },
                set: { viewModel.setSortOrder($0) }
            )
        )
    }

    private var filterControl: some View {
        Button { showFilterSheet = true } label: {
            controlPill(
                title: viewModel.activeFilterCount == 0
                    ? "Filter"
                    : "Filter \(viewModel.activeFilterCount)",
                symbol: "line.3.horizontal.decrease",
                isActive: viewModel.hasActiveFilters
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Filter and sort files")
        .accessibilityValue(viewModel.refinementAccessibilityValue)
        .accessibilityHint("Opens file type, date, and sorting options")
    }

    private func controlPill(
        title: String,
        symbol: String,
        isActive: Bool
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.xSmall) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(AppTheme.Typography.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(AppTheme.Colors.label)
        .padding(.horizontal, AppTheme.Spacing.medium)
        .frame(minHeight: 44)
        .background(isActive ? AppTheme.Colors.accent.opacity(AppTheme.Selection.selectedWash) : AppTheme.Colors.secondaryBG)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(isActive ? AppTheme.Colors.accent : AppTheme.Colors.separator.opacity(0.45),
                              lineWidth: AppTheme.Selection.borderWidth)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var activeFilterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(FileType.allCases.filter(viewModel.selectedFileTypes.contains), id: \.self) { type in
                    filterChip(title: type.displayName, symbol: type.sfSymbol) {
                        viewModel.removeFileType(type)
                    }
                }

                if viewModel.filterDateStart != nil || viewModel.filterDateEnd != nil {
                    filterChip(
                        title: viewModel.dateFilterSummary,
                        symbol: "calendar"
                    ) {
                        viewModel.clearDateFilter()
                    }
                }

                Button("Clear") { viewModel.clearFilters() }
                    .font(AppTheme.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .frame(minHeight: 44)
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 1, for: .scrollContent)
    }

    private func filterChip(
        title: String,
        symbol: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        Button(action: onRemove) {
            HStack(spacing: AppTheme.Spacing.xSmall) {
                Image(systemName: symbol)
                Text(title)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .font(AppTheme.Typography.caption1.weight(.semibold))
            .foregroundStyle(AppTheme.Colors.secondaryLabel)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .frame(minHeight: 44)
            .background(AppTheme.Colors.secondaryBG)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(title) filter")
    }

    // MARK: - Content

    @ViewBuilder
    private var filesContent: some View {
        if viewModel.items.isEmpty && !viewModel.isLoadingMore {
            EmptyStateView(
                symbol: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle" : "doc.on.doc",
                title: viewModel.hasActiveFilters ? "No matching files" : "No files",
                subtitle: viewModel.hasActiveFilters
                    ? "Try removing a filter to broaden your library."
                    : "Tap + to add your first file.",
                placement: .page,
                actionLabel: viewModel.hasActiveFilters ? "Clear Filters" : nil,
                action: viewModel.hasActiveFilters ? { viewModel.clearFilters() } : nil
            )
        } else {
            Group {
                switch viewModel.layoutStyle {
                case .list:
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.items) { item in
                            itemCell(item, style: .row)
                            if item.id != viewModel.items.last?.id {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                    .background(AppTheme.Colors.flatCard)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
                    .padding(.horizontal, AppTheme.Spacing.base)
                case .grid:
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 156, maximum: 260),
                                spacing: AppTheme.Spacing.medium
                            )
                        ],
                        spacing: AppTheme.Spacing.medium
                    ) {
                        ForEach(viewModel.items) { item in
                            itemCell(item, style: .grid)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.base)
                }
            }
            .padding(.vertical, AppTheme.Spacing.small)

            scrollSentinel
        }
    }

    // MARK: - Item cell

    @ViewBuilder
    private func itemCell(_ item: Item, style: ItemCardView.Style) -> some View {
        let isSelected = viewModel.selectedIDs.contains(item.id)
        Button {
            if viewModel.isSelectMode {
                viewModel.toggleSelection(item)
            } else {
                fileViewer.open(item)
            }
        } label: {
            FilesItemView(
                item: item,
                style: style,
                isSelectMode: viewModel.isSelectMode,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(viewModel.isSelectMode && isSelected ? "Selected" : "")
    }

    // MARK: - Infinite scroll sentinel

    @ViewBuilder
    private var scrollSentinel: some View {
        if viewModel.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.xLarge)
        } else if viewModel.hasMorePages {
            Color.clear
                .frame(height: 1)
                .onAppear { viewModel.loadNextPage() }
        }
    }
}

/// Quiet library presentation, following the compact rows in Home collections.
private struct FilesItemView: View {
    let item: Item
    let style: ItemCardView.Style
    let isSelectMode: Bool
    let isSelected: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var statusSlotSize: CGFloat = 16

    private var subtitle: String {
        var parts = [item.fileType.displayName]
        if let tag = item.tags.first {
            parts.append(item.tags.count > 1 ? "\(tag.name) +\(item.tags.count - 1)" : tag.name)
        }
        return parts.joined(separator: " · ")
    }

    private var icon: some View {
        Image(systemName: item.fileType.sfSymbol)
            .font(.title3)
            .foregroundStyle(item.fileType.tintColor)
            .frame(width: 40, height: 44)
            .background(item.fileType.tintColor.opacity(AppTheme.Tint.wash),
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text(item.title)
                .font(AppTheme.Typography.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.Colors.label)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(AppTheme.Typography.caption1)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            if dynamicTypeSize.isAccessibilitySize || style == .grid {
                metadata
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadata: some View {
        VStack(alignment: style == .row && !dynamicTypeSize.isAccessibilitySize ? .trailing : .leading,
               spacing: AppTheme.Spacing.xSmall) {
            Text(item.modifiedAt.compactRelativeString)
                .monospacedDigit()
                .fixedSize()
                .accessibilityLabel("Modified \(item.modifiedAt.relativeString)")
                .font(AppTheme.Typography.caption2)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
            HStack(spacing: AppTheme.Spacing.xSmall) {
                if item.syncStatus != .synced && item.syncStatus != .localOnly {
                    SyncStatusBadge(status: item.syncStatus, compactMode: true)
                        .frame(width: statusSlotSize, height: statusSlotSize)
                }
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .frame(width: statusSlotSize, height: statusSlotSize)
                        .accessibilityLabel("Pinned")
                }
                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .frame(width: statusSlotSize, height: statusSlotSize)
                        .accessibilityLabel("Favorite")
                }
            }
            .frame(minHeight: statusSlotSize)
            .font(.caption2)
            .foregroundStyle(AppTheme.Colors.secondaryLabel)
        }
    }

    private var selection: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.secondaryLabel)
            .accessibilityHidden(true)
    }

    var body: some View {
        Group {
            if style == .row {
                HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                    if isSelectMode { selection }
                    icon
                    details
                    if !dynamicTypeSize.isAccessibilitySize { metadata }
                    if !isSelectMode {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                            .accessibilityHidden(true)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    HStack {
                        icon
                        Spacer()
                        if isSelectMode { selection }
                    }
                    details
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(isSelected ? AppTheme.Colors.accent.opacity(0.08) : AppTheme.Colors.flatCard)
        .clipShape(RoundedRectangle(cornerRadius: style == .grid ? AppTheme.Radius.large : 0))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// Keeps the menu's footprint stable while its selected value changes. SwiftUI's
// Menu can otherwise retain a shorter intermediate label width and clip the next
// value until another layout pass.
struct FilesSortMenu: View {

    @Binding var selection: SearchService.SortOrder

    var body: some View {
        Menu {
            Picker("Sort files", selection: $selection) {
                ForEach(SearchService.SortOrder.allOptions, id: \.self) { option in
                    Label(option.title, systemImage: option.symbol)
                        .tag(option)
                }
            }
        } label: {
            FilesSortPillLabel(sortOrder: selection)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Sort files")
        .accessibilityValue(selection.title)
        .accessibilityHint("Choose how files are ordered")
    }
}

struct FilesSortPillLabel: View {

    let sortOrder: SearchService.SortOrder

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xSmall) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption.weight(.semibold))

            ZStack(alignment: .leading) {
                ForEach(SearchService.SortOrder.allOptions, id: \.self) { option in
                    Text(option.shortTitle)
                        .opacity(option == sortOrder ? 1 : 0)
                        .accessibilityHidden(option != sortOrder)
                }
            }
            .font(AppTheme.Typography.subheadline.weight(.semibold))
            .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .opacity(0.7)
        }
        .foregroundStyle(AppTheme.Colors.label)
        .padding(.horizontal, AppTheme.Spacing.medium)
        .frame(minHeight: 44)
        .background(
            sortOrder == .modifiedAt
                ? AppTheme.Colors.secondaryBG
                : AppTheme.Colors.accent.opacity(AppTheme.Selection.selectedWash)
        )
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    sortOrder == .modifiedAt
                        ? AppTheme.Colors.separator.opacity(0.45)
                        : AppTheme.Colors.accent,
                    lineWidth: AppTheme.Selection.borderWidth
                )
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Files filter and sort sheet

private struct FilesFilterSheetView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onApply: (Set<FileType>, SearchService.SortOrder, Date?, Date?) -> Void

    @State private var localTypes: Set<FileType>
    @State private var localSort: SearchService.SortOrder
    @State private var localStart: Date?
    @State private var localEnd: Date?
    @State private var includeStart: Bool
    @State private var includeEnd: Bool
    @State private var isFileTypePickerExpanded = false

    init(
        selectedFileTypes: Set<FileType>,
        sortOrder: SearchService.SortOrder,
        filterDateStart: Date?,
        filterDateEnd: Date?,
        onApply: @escaping (Set<FileType>, SearchService.SortOrder, Date?, Date?) -> Void
    ) {
        _localTypes = State(initialValue: selectedFileTypes)
        _localSort = State(initialValue: sortOrder)
        _localStart = State(initialValue: filterDateStart)
        _localEnd = State(initialValue: filterDateEnd)
        _includeStart = State(initialValue: filterDateStart != nil)
        _includeEnd = State(initialValue: filterDateEnd != nil)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Refine files") {
                    fileTypeDisclosure
                    dateMenuRow
                    sortMenuRow

                    if selectedDatePreset == nil {
                        customDateRange
                            .padding(.vertical, AppTheme.Spacing.xSmall)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.groupedBG)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset") { resetAll() }
                        .disabled(!hasLocalRefinements)
                        .accessibilityHint("Restores all file types, any date, and Last Modified sorting")
                }
            }
            .safeAreaInset(edge: .bottom) {
                applyBar
            }
        }
    }

    private var fileTypeDisclosure: some View {
        DisclosureGroup(isExpanded: $isFileTypePickerExpanded) {
            fileTypeSelector
                .padding(.vertical, AppTheme.Spacing.xSmall)
        } label: {
            fileTypeDisclosureLabel
        }
        .tint(AppTheme.Colors.accent)
        .accessibilityLabel("File type")
        .accessibilityValue(fileTypeSelectionSummary)
        .accessibilityHint(isFileTypePickerExpanded
                           ? "Collapses the file type choices"
                           : "Expands choices that allow multiple file types")
    }

    @ViewBuilder
    private var fileTypeDisclosureLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                Label("File type", systemImage: "doc.on.doc")
                    .foregroundStyle(AppTheme.Colors.label)
                Text(fileTypeSelectionSummary)
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(AppTheme.Colors.accent)
                Text("File type")
                Spacer()
                Text(fileTypeSelectionSummary)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .lineLimit(1)
            }
            .font(AppTheme.Typography.subheadline)
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var fileTypeSelector: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: fileTypeColumns, spacing: AppTheme.Spacing.small) {
                allTypesButton(fillWidth: true)
                ForEach(FileType.allCases, id: \.self) { type in
                    typeButton(type, fillWidth: true)
                }
            }
        } else {
            ScrollView(.horizontal) {
                LazyHGrid(rows: compactFileTypeRows, spacing: AppTheme.Spacing.small) {
                    allTypesButton(fillWidth: false)
                    ForEach(FileType.allCases, id: \.self) { type in
                        typeButton(type, fillWidth: false)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: 96)
            .accessibilityHint("Swipe horizontally for more file types")
        }
    }

    private func allTypesButton(fillWidth: Bool) -> some View {
        Button {
            localTypes.removeAll()
        } label: {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(AppTheme.Colors.accent)
                Text("All")
                    .lineLimit(1)
                Spacer(minLength: 2)
                if localTypes.isEmpty {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                }
            }
            .font(AppTheme.Typography.caption1.weight(.semibold))
            .foregroundStyle(AppTheme.Colors.label)
            .padding(.horizontal, AppTheme.Spacing.small)
            .frame(
                minWidth: fillWidth ? nil : 84,
                maxWidth: fillWidth ? .infinity : nil,
                minHeight: 44,
                alignment: .leading
            )
            .background(AppTheme.Colors.accent.opacity(
                localTypes.isEmpty ? AppTheme.Selection.selectedWash : AppTheme.Selection.restingWash))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .strokeBorder(localTypes.isEmpty ? AppTheme.Colors.accent : .clear,
                                  lineWidth: AppTheme.Selection.borderWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All file types")
        .accessibilityValue(localTypes.isEmpty ? "Selected" : "Not selected")
        .accessibilityHint(localTypes.isEmpty
                           ? "All file types are included"
                           : "Includes every file type")
        .accessibilityAddTraits(localTypes.isEmpty ? .isSelected : [])
    }

    private func typeButton(_ type: FileType, fillWidth: Bool) -> some View {
        let isSelected = localTypes.contains(type)

        return Button {
            if isSelected {
                localTypes.remove(type)
            } else {
                localTypes.insert(type)
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xSmall) {
                Image(systemName: type.sfSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(type.tintColor)
                Text(type.displayName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(type.tintColor)
                }
            }
            .font(AppTheme.Typography.caption1.weight(.semibold))
            .foregroundStyle(AppTheme.Colors.label)
            .padding(.horizontal, AppTheme.Spacing.small)
            .frame(
                minWidth: fillWidth ? nil : 92,
                maxWidth: fillWidth ? .infinity : nil,
                minHeight: 44,
                alignment: .leading
            )
            .background(type.tintColor.opacity(
                isSelected ? AppTheme.Selection.selectedWash : AppTheme.Selection.restingWash))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .strokeBorder(isSelected ? type.tintColor : .clear, lineWidth: AppTheme.Selection.borderWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.displayName) files")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected
                           ? "Removes this file type from the results"
                           : "Includes this file type in the results")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sortMenuRow: some View {
        Menu {
            ForEach(SearchService.SortOrder.allOptions, id: \.self) { option in
                Button {
                    localSort = option
                } label: {
                    Label(
                        option.title,
                        systemImage: localSort == option ? "checkmark" : option.symbol
                    )
                }
            }
        } label: {
            compactMenuLabel(
                title: "Sort by",
                value: localSort.title,
                symbol: "arrow.up.arrow.down"
            )
        }
        .foregroundStyle(AppTheme.Colors.label)
        .accessibilityLabel("Sort files")
        .accessibilityValue(localSort.title)
        .accessibilityHint("Choose how files are ordered")
    }

    private var dateMenuRow: some View {
        Menu {
            datePresetMenuButton("Any time", symbol: "calendar", preset: .anyTime)
            datePresetMenuButton("Last 7 days", symbol: "calendar.badge.clock", preset: .lastSevenDays)
            datePresetMenuButton("Last 30 days", symbol: "calendar.badge.clock", preset: .lastThirtyDays)
            datePresetMenuButton("This year", symbol: "calendar", preset: .thisYear)
            Divider()
            Button {
                activateCustomDateRange()
            } label: {
                Label(
                    "Custom range",
                    systemImage: selectedDatePreset == nil ? "checkmark" : "calendar.badge.plus"
                )
            }
        } label: {
            compactMenuLabel(
                title: "Date added",
                value: dateMenuTitle,
                symbol: "calendar"
            )
        }
        .foregroundStyle(AppTheme.Colors.label)
        .accessibilityLabel("Date added")
        .accessibilityValue(dateMenuTitle)
        .accessibilityHint("Choose when matching files were added")
    }

    private func compactMenuLabel(title: String, value: String, symbol: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                    Label(title, systemImage: symbol)
                    Text(value)
                        .font(AppTheme.Typography.caption1)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: symbol)
                        .foregroundStyle(AppTheme.Colors.accent)
                    Text(title)
                    Spacer()
                    Text(value)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                }
            }
        }
        .font(AppTheme.Typography.subheadline)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func datePresetMenuButton(_ title: String, symbol: String, preset: DatePreset) -> some View {
        Button {
            applyDatePreset(preset)
        } label: {
            Label(title, systemImage: selectedDatePreset == preset ? "checkmark" : symbol)
        }
    }

    private var customDateRange: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            Toggle("Start date", isOn: $includeStart)
                .font(AppTheme.Typography.subheadline)
                .accessibilityHint("Limits results to files added on or after a chosen date")

            if includeStart {
                DatePicker(
                    "From",
                    selection: Binding(
                        get: { localStart ?? defaultStartDate },
                        set: { localStart = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .font(AppTheme.Typography.subheadline)
            }

            Toggle("End date", isOn: $includeEnd)
                .font(AppTheme.Typography.subheadline)
                .accessibilityHint("Limits results to files added on or before a chosen date")

            if includeEnd {
                DatePicker(
                    "Through",
                    selection: Binding(
                        get: { localEnd ?? Date() },
                        set: { localEnd = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .font(AppTheme.Typography.subheadline)
            }
        }
        .tint(AppTheme.Colors.accent)
    }

    private var applyBar: some View {
        Button {
            let start = includeStart ? (localStart ?? defaultStartDate) : nil
            let end = includeEnd ? (localEnd ?? Date()) : nil
            onApply(localTypes, localSort, start, end)
            dismiss()
        } label: {
            HStack {
                Text("Show Files")
                    .font(AppTheme.Typography.headline)
                Spacer()
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(applySummary)
                        .font(AppTheme.Typography.subheadline)
                        .opacity(0.85)
                }
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.base)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(AppTheme.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show files")
        .accessibilityValue(applyAccessibilitySummary)
        .accessibilityHint("Closes this panel and updates the file list")
        .padding(.horizontal, AppTheme.Spacing.base)
        .padding(.vertical, AppTheme.Spacing.small)
        .background {
            if reduceTransparency {
                AppTheme.Colors.background
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .top) { Divider() }
    }

    private var dateSelectionSummary: String {
        switch (includeStart, includeEnd) {
        case (false, false):
            return "Any time"
        case (true, false):
            return "From \((localStart ?? defaultStartDate).formatted(date: .abbreviated, time: .omitted))"
        case (false, true):
            return "Through \((localEnd ?? Date()).formatted(date: .abbreviated, time: .omitted))"
        case (true, true):
            let start = (localStart ?? defaultStartDate).formatted(date: .abbreviated, time: .omitted)
            let end = (localEnd ?? Date()).formatted(date: .abbreviated, time: .omitted)
            return "\(start) – \(end)"
        }
    }

    private var fileTypeSelectionSummary: String {
        localTypes.isEmpty ? "All" : "\(localTypes.count) selected"
    }

    private var dateMenuTitle: String {
        switch selectedDatePreset {
        case .anyTime:        return "Any time"
        case .lastSevenDays:  return "Last 7 days"
        case .lastThirtyDays: return "Last 30 days"
        case .thisYear:       return "This year"
        case nil:             return "Custom range"
        }
    }

    private var applySummary: String {
        let count = localTypes.count + ((includeStart || includeEnd) ? 1 : 0)
        return count == 0
            ? localSort.shortTitle
            : "\(count) filter\(count == 1 ? "" : "s") · \(localSort.shortTitle)"
    }

    private var applyAccessibilitySummary: String {
        let typeSummary = localTypes.isEmpty
            ? "All file types"
            : "\(localTypes.count) file type\(localTypes.count == 1 ? "" : "s")"
        let dateSummary = includeStart || includeEnd ? dateSelectionSummary : "Any date"
        return "\(typeSummary). \(dateSummary). Sorted by \(localSort.title)"
    }

    private var hasLocalRefinements: Bool {
        !localTypes.isEmpty || localSort != .modifiedAt || includeStart || includeEnd
    }

    private var defaultStartDate: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    }

    private var fileTypeColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 180),
                spacing: AppTheme.Spacing.small
            )
        ]
    }

    private var compactFileTypeRows: [GridItem] {
        [
            GridItem(.fixed(44), spacing: AppTheme.Spacing.small),
            GridItem(.fixed(44), spacing: AppTheme.Spacing.small)
        ]
    }

    private var selectedDatePreset: DatePreset? {
        guard includeStart || includeEnd else { return .anyTime }
        guard includeStart, !includeEnd, let start = localStart else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let week = calendar.date(byAdding: .day, value: -7, to: today),
           calendar.isDate(start, inSameDayAs: week) {
            return .lastSevenDays
        }
        if let month = calendar.date(byAdding: .day, value: -30, to: today),
           calendar.isDate(start, inSameDayAs: month) {
            return .lastThirtyDays
        }
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: today))
        if let yearStart, calendar.isDate(start, inSameDayAs: yearStart) {
            return .thisYear
        }
        return nil
    }

    private func applyDatePreset(_ preset: DatePreset) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        includeEnd = false
        localEnd = nil

        switch preset {
        case .anyTime:
            includeStart = false
            localStart = nil
        case .lastSevenDays:
            includeStart = true
            localStart = calendar.date(byAdding: .day, value: -7, to: today)
        case .lastThirtyDays:
            includeStart = true
            localStart = calendar.date(byAdding: .day, value: -30, to: today)
        case .thisYear:
            includeStart = true
            localStart = calendar.date(from: calendar.dateComponents([.year], from: today))
        }
    }

    private func activateCustomDateRange() {
        includeStart = true
        includeEnd = true
        if localStart == nil {
            localStart = defaultStartDate
        }
        if localEnd == nil {
            localEnd = Date()
        }
    }

    private func resetAll() {
        localTypes.removeAll()
        localSort = .modifiedAt
        localStart = nil
        localEnd = nil
        includeStart = false
        includeEnd = false
    }

    private enum DatePreset {
        case anyTime
        case lastSevenDays
        case lastThirtyDays
        case thisYear
    }
}

// MARK: - Sort presentation

private extension SearchService.SortOrder {
    static let allOptions: [Self] = [.modifiedAt, .createdAt, .title, .viewCount, .fileSize]

    var title: String {
        switch self {
        case .modifiedAt: return "Last Modified"
        case .createdAt:  return "Recently Added"
        case .title:      return "Name"
        case .viewCount:  return "Most Opened"
        case .fileSize:   return "Largest First"
        }
    }

    var shortTitle: String {
        switch self {
        case .modifiedAt: return "Modified"
        case .createdAt:  return "Added"
        case .title:      return "Name"
        case .viewCount:  return "Opened"
        case .fileSize:   return "Size"
        }
    }

    var detail: String {
        switch self {
        case .modifiedAt: return "Most recently changed first"
        case .createdAt:  return "Newest additions first"
        case .title:      return "Alphabetical, A to Z"
        case .viewCount:  return "Most frequently opened first"
        case .fileSize:   return "Largest files first"
        }
    }

    var symbol: String {
        switch self {
        case .modifiedAt: return "clock.arrow.circlepath"
        case .createdAt:  return "calendar.badge.plus"
        case .title:      return "textformat"
        case .viewCount:  return "eye"
        case .fileSize:   return "arrow.down"
        }
    }
}

// MARK: - Preview

#Preview {
    FilesView()
        .modelContainer(PersistenceController.preview.container)
        .environment(AppContainer())
        .environment(FileViewerCoordinator())
}
