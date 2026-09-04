import SwiftUI

/// A semantic row in the expandable tag hierarchy.
struct TagNodeView: View {
    let tag: Tag
    let depth: Int
    let visibleChildren: (Tag) -> [Tag]
    @Binding var expandedIDs: Set<UUID>
    var onSelect: (Tag) -> Void
    var onCreateChild: (Tag) -> Void
    var onMove: (Tag) -> Void
    var onEdit: (Tag) -> Void
    var onDelete: (Tag) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var children: [Tag] { visibleChildren(tag) }
    private var isExpanded: Bool { expandedIDs.contains(tag.id) }
    private var cappedDepth: Int { min(depth, dynamicTypeSize.isAccessibilitySize ? 3 : 6) }

    var body: some View {
        VStack(spacing: 0) {
            row

            if !children.isEmpty && isExpanded {
                ForEach(children) { child in
                    Divider()
                        .padding(.leading, rowLeadingPadding + 44)
                    TagNodeView(
                        tag: child,
                        depth: depth + 1,
                        visibleChildren: visibleChildren,
                        expandedIDs: $expandedIDs,
                        onSelect: onSelect,
                        onCreateChild: onCreateChild,
                        onMove: onMove,
                        onEdit: onEdit,
                        onDelete: onDelete
                    )
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 0) {
            if !children.isEmpty {
                Button {
                    if reduceMotion {
                        toggleExpansion()
                    } else {
                        withAnimation(AppTheme.Animation.snappy) { toggleExpansion() }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 44, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse \(tag.name)" : "Expand \(tag.name)")
            } else {
                Color.clear
                    .frame(width: 44, height: 52)
                    .accessibilityHidden(true)
            }

            Button { onSelect(tag) } label: {
                HStack(spacing: AppTheme.Spacing.medium) {
                    tagIcon

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                        Text(tag.name)
                            .font(AppTheme.Typography.body)
                            .foregroundStyle(AppTheme.Colors.label)
                            .multilineTextAlignment(.leading)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                        if !tag.children.isEmpty {
                            Text("\(tag.children.count) subtag\(tag.children.count == 1 ? "" : "s")")
                                .font(AppTheme.Typography.caption1)
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        }
                    }

                    Spacer(minLength: AppTheme.Spacing.small)

                    if tag.totalItemCount > 0 {
                        Text("\(tag.totalItemCount)")
                            .font(AppTheme.Typography.caption1.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            .padding(.horizontal, AppTheme.Spacing.small)
                            .padding(.vertical, AppTheme.Spacing.xSmall)
                            .background(AppTheme.Colors.fill, in: Capsule())
                            .accessibilityLabel("\(tag.totalItemCount) files including subtags")
                    }

                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        .accessibilityHidden(true)
                }
                .padding(.trailing, AppTheme.Spacing.base)
                .padding(.vertical, AppTheme.Spacing.small)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tag.name)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Opens files for this tag")
        }
        .padding(.leading, rowLeadingPadding)
        .background(alignment: .leading) {
            if depth > 0 {
                Rectangle()
                    .fill(AppTheme.Colors.separator.opacity(0.45))
                    .frame(width: 2)
                    .padding(.leading, max(7, rowLeadingPadding - 10))
                    .accessibilityHidden(true)
            }
        }
        .contextMenu { actionMenu }
        .accessibilityAction(named: "Add Subtag") { onCreateChild(tag) }
        .accessibilityAction(named: "Move Tag") { onMove(tag) }
        .accessibilityAction(named: "Edit Tag") { onEdit(tag) }
        .accessibilityAction(named: "Delete Tag") { onDelete(tag) }
    }

    private var tagIcon: some View {
        TagSymbolView(
            sfSymbol: tag.sfSymbol,
            color: Color(hex: tag.colorHex),
            size: 16
        )
        .frame(width: 32, height: 32)
        .background(Color(hex: tag.colorHex).opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var actionMenu: some View {
        Button { onCreateChild(tag) } label: {
            Label("Add Subtag", systemImage: "plus")
        }
        Button { onMove(tag) } label: {
            Label("Move Tag", systemImage: "folder")
        }
        Button { onEdit(tag) } label: {
            Label("Edit Tag", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) { onDelete(tag) } label: {
            Label("Delete Tag", systemImage: "trash")
        }
    }

    private var rowLeadingPadding: CGFloat {
        CGFloat(cappedDepth) * (dynamicTypeSize.isAccessibilitySize ? 12 : 18)
    }

    private var accessibilityValue: String {
        var parts = ["Level \(depth + 1)"]
        if !tag.children.isEmpty {
            parts.append("\(tag.children.count) subtags")
            parts.append(isExpanded ? "expanded" : "collapsed")
        }
        if tag.totalItemCount > 0 {
            parts.append("\(tag.totalItemCount) files including subtags")
        }
        return parts.joined(separator: ", ")
    }

    private func toggleExpansion() {
        if isExpanded {
            expandedIDs.remove(tag.id)
        } else {
            expandedIDs.insert(tag.id)
        }
    }
}
