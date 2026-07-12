import SwiftUI

/// A single row in the tag tree with expand/collapse, swipe actions, and context menu.
struct TagNodeView: View {

    let tag: Tag
    let depth: Int
    let allTags: [Tag]           // needed to populate "Set Parent" menu
    @Binding var expandedIDs: Set<UUID>
    var onSelect: (Tag) -> Void
    var onCreateChild: (Tag) -> Void
    var onRename: (Tag) -> Void
    var onDelete: (Tag) -> Void
    var onSetParent: (Tag) -> Void
    var onMakeTopLevel: (Tag) -> Void

    private var isExpanded: Bool { expandedIDs.contains(tag.id) }
    private var isChild: Bool {
        allTags.contains { $0.children.contains(where: { $0.id == tag.id }) }
    }
    private let stepWidth: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            row
            if !tag.children.isEmpty && isExpanded {
                ForEach(tag.children.sorted { $0.name < $1.name }) { child in
                    TagNodeView(
                        tag: child,
                        depth: depth + 1,
                        allTags: allTags,
                        expandedIDs: $expandedIDs,
                        onSelect: onSelect,
                        onCreateChild: onCreateChild,
                        onRename: onRename,
                        onDelete: onDelete,
                        onSetParent: onSetParent,
                        onMakeTopLevel: onMakeTopLevel
                    )
                }
            }
        }
    }

    // MARK: - Row

    private var row: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            // Indentation
            if depth > 0 {
                Spacer().frame(width: CGFloat(depth) * stepWidth)
            }

            // Expand / collapse chevron
            if !tag.children.isEmpty {
                Button {
                    withAnimation(AppTheme.Animation.snappy) {
                        if isExpanded { expandedIDs.remove(tag.id) }
                        else { expandedIDs.insert(tag.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(AppTheme.Animation.snappy, value: isExpanded)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 16)
            }

            // Tag icon
            TagSymbolView(sfSymbol: tag.sfSymbol, color: Color(hex: tag.colorHex), size: 14)
                .frame(width: 22, height: 22)
                .background(Color(hex: tag.colorHex).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Name + subtag hint
            VStack(alignment: .leading, spacing: 1) {
                Text(tag.name)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.label)
                    .lineLimit(1)
                if !tag.children.isEmpty {
                    Text("\(tag.children.count) subtag\(tag.children.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                }
            }

            Spacer()

            // Item count badge
            if tag.totalItemCount > 0 {
                Text("\(tag.totalItemCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.Colors.fill)
                    .clipShape(Capsule())
            }

        }
        .padding(.vertical, AppTheme.Spacing.medium)
        .padding(.horizontal, AppTheme.Spacing.base)
        // Vertical tree lines drawn with Canvas so positions are absolute from (0,0) = row's top-left.
        // .background{} centers its content by default, making ZStack/Color positioning unreliable.
        // Canvas receives the exact row bounds and draws lines at precise x positions.
        .background {
            if depth > 0 {
                let d = depth
                let step = stepWidth
                Canvas { ctx, size in
                    for level in 0..<d {
                        // Middle of each indent segment: base leading padding + level offset + half step
                        let x = AppTheme.Spacing.base + CGFloat(level) * step + step * 0.5
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(path, with: .color(Color(UIColor.separator).opacity(0.5)), lineWidth: 2)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(tag) }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { onCreateChild(tag) } label: {
                Label("Add Child", systemImage: "plus.circle.fill")
            }
            .tint(AppTheme.Colors.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDelete(tag) } label: {
                Label("Delete", systemImage: "trash.fill")
            }
            Button { onRename(tag) } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button { onCreateChild(tag) } label: {
                Label("New Child Tag", systemImage: "plus.circle")
            }
            Button { onSetParent(tag) } label: {
                Label("Set Parent...", systemImage: "arrow.up.to.line")
            }
            if isChild {
                Button { onMakeTopLevel(tag) } label: {
                    Label("Make Top-Level", systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                }
            }
            Divider()
            Button { onRename(tag) } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) { onDelete(tag) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
