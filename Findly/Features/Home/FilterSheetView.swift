import SwiftUI

struct FilterSheetView: View {

    @Binding var selectedFileTypes: Set<FileType>
    @Binding var sortOrder: SearchService.SortOrder
    @Binding var filterDateStart: Date?
    @Binding var filterDateEnd: Date?

    @Environment(\.dismiss) private var dismiss

    // Local copies edited before applying
    @State private var localTypes: Set<FileType>
    @State private var localSort: SearchService.SortOrder
    @State private var localStart: Date?
    @State private var localEnd: Date?
    @State private var enableStart = false
    @State private var enableEnd = false

    init(
        selectedFileTypes: Binding<Set<FileType>>,
        sortOrder: Binding<SearchService.SortOrder>,
        filterDateStart: Binding<Date?>,
        filterDateEnd: Binding<Date?>
    ) {
        _selectedFileTypes = selectedFileTypes
        _sortOrder = sortOrder
        _filterDateStart = filterDateStart
        _filterDateEnd = filterDateEnd
        _localTypes = State(initialValue: selectedFileTypes.wrappedValue)
        _localSort = State(initialValue: sortOrder.wrappedValue)
        _localStart = State(initialValue: filterDateStart.wrappedValue)
        _localEnd = State(initialValue: filterDateEnd.wrappedValue)
        _enableStart = State(initialValue: filterDateStart.wrappedValue != nil)
        _enableEnd = State(initialValue: filterDateEnd.wrappedValue != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: File type
                Section("File Type") {
                    LazyVGrid(
                        columns: Array(repeating: .init(.flexible()), count: 3),
                        spacing: AppTheme.Spacing.small
                    ) {
                        ForEach(FileType.allCases, id: \.self) { type in
                            typeChip(type)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.xSmall)
                }

                // MARK: Sort
                Section("Sort By") {
                    Picker("Sort", selection: $localSort) {
                        Text("Last Modified").tag(SearchService.SortOrder.modifiedAt)
                        Text("Date Added").tag(SearchService.SortOrder.createdAt)
                        Text("Name (A–Z)").tag(SearchService.SortOrder.title)
                        Text("Most Opened").tag(SearchService.SortOrder.viewCount)
                        Text("Largest First").tag(SearchService.SortOrder.fileSize)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // MARK: Date range
                Section("Added Date") {
                    Toggle("After", isOn: $enableStart)
                    if enableStart {
                        DatePicker(
                            "Start",
                            selection: Binding(
                                get: { localStart ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())! },
                                set: { localStart = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }

                    Toggle("Before", isOn: $enableEnd)
                    if enableEnd {
                        DatePicker(
                            "End",
                            selection: Binding(
                                get: { localEnd ?? Date() },
                                set: { localEnd = $0 }
                            ),
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                }

                // Reset
                Section {
                    Button("Reset Filters", role: .destructive) {
                        localTypes = []
                        localSort = .modifiedAt
                        localStart = nil
                        localEnd = nil
                        enableStart = false
                        enableEnd = false
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        selectedFileTypes = localTypes
                        sortOrder = localSort
                        filterDateStart = enableStart ? localStart : nil
                        filterDateEnd = enableEnd ? localEnd : nil
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func typeChip(_ type: FileType) -> some View {
        let selected = localTypes.contains(type)
        return Button {
            if selected { localTypes.remove(type) } else { localTypes.insert(type) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: type.sfSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? .white : type.tintColor)
                Text(type.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selected ? .white : AppTheme.Colors.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(selected ? type.tintColor : type.tintColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
