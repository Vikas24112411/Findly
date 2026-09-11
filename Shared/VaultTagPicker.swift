import SwiftUI

struct VaultTagOption: Identifiable {
    let id: UUID
    let name: String
    var colorHex = "#4A90E2"
    var sfSymbol = "tag.fill"
}

struct VaultTagPicker: View {
    let tags: [VaultTagOption]
    @Binding var selectedIDs: Set<UUID>
    let createTag: (String) -> Void
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [VaultTagOption] {
        tags.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.name < $1.name }
    }
    private var canCreate: Bool {
        !query.isEmpty && !tags.contains { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.Colors.secondaryLabel)
                    TextField("Search tags...", text: $searchText)
                        .accessibilityLabel("Search tags")
                }
                .padding(AppTheme.Spacing.medium)
                .background {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(AppTheme.Colors.secondaryBG)
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(.ultraThinMaterial)
                    }
                }
                .padding(AppTheme.Spacing.base)
                if !selectedIDs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.small) {
                            ForEach(tags.filter { selectedIDs.contains($0.id) }.sorted { $0.name < $1.name }) { tag in
                                VaultTagChip(tag: tag) { selectedIDs.remove(tag.id) }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.base)
                    }
                    .padding(.bottom, AppTheme.Spacing.small)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filtered.isEmpty && !canCreate {
                            ContentUnavailableView("No tags", systemImage: "tag.slash", description: Text("Type a name to create one."))
                        }
                        if canCreate {
                            Button {
                                createTag(query)
                                searchText = ""
                            } label: {
                                HStack(spacing: AppTheme.Spacing.medium) {
                                    Image(systemName: "plus.circle.fill")
                                        .frame(width: 28, height: 28)
                                        .background(AppTheme.Colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    Text("Create \"\(query)\"")
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .padding(.horizontal, AppTheme.Spacing.base)
                                .padding(.vertical, AppTheme.Spacing.medium)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.Colors.accent)
                            Divider().padding(.leading, 56)
                        }
                        ForEach(filtered) { tag in
                            let selected = selectedIDs.contains(tag.id)
                            Button {
                                if selected { selectedIDs.remove(tag.id) } else { selectedIDs.insert(tag.id) }
                            } label: {
                                HStack(spacing: AppTheme.Spacing.medium) {
                                    VaultTagSymbol(tag: tag, color: Color(hex: tag.colorHex), size: 16)
                                        .frame(width: 28, height: 28)
                                        .background(Color(hex: tag.colorHex).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                    Text(tag.name)
                                        .font(AppTheme.Typography.body)
                                        .foregroundStyle(AppTheme.Colors.label)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.Colors.accent)
                                    }
                                }
                                .padding(.horizontal, AppTheme.Spacing.base)
                                .padding(.vertical, AppTheme.Spacing.medium)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            Divider().padding(.leading, 56)
                        }
                    }
                    .background(AppTheme.Colors.secondaryBG)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
                    .padding(.horizontal, AppTheme.Spacing.base)
                }
            }
            .background(AppTheme.Colors.groupedBG)
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(AppTheme.Colors.accent)
    }
}

struct VaultTagChip: View {
    let tag: VaultTagOption
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: AppTheme.Spacing.xSmall) {
                VaultTagSymbol(tag: tag, color: .white, size: 11)
                Text(tag.name).font(AppTheme.Typography.caption1.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.xSmall)
            .background(Color(hex: tag.colorHex), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove tag \(tag.name)")
    }
}

private struct VaultTagSymbol: View {
    let tag: VaultTagOption
    let color: Color
    let size: CGFloat
    var body: some View {
        Group {
            if tag.sfSymbol.unicodeScalars.allSatisfy({ $0.value < 128 }) {
                Image(systemName: tag.sfSymbol).foregroundStyle(color)
            } else {
                Text(tag.sfSymbol)
            }
        }
        .font(.system(size: size, weight: .medium))
        .accessibilityHidden(true)
    }
}

/// Proposes the available width to long tags so large text wraps within the sheet.
struct VaultTagFlowLayout: Layout {
    var spacing: CGFloat = 8

    private func positions(width: CGFloat, subviews: Subviews) -> (CGSize, [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        positions(width: proposal.width ?? 320, subviews: subviews).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let frames = positions(width: bounds.width, subviews: subviews).1
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }
}
