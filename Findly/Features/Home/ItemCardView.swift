import SwiftUI

/// Reusable item card that supports grid and row display styles.
struct ItemCardView: View {

    let item: Item
    var style: Style = .grid
    var isSelectMode: Bool = false
    var isSelected: Bool = false
    var titleLines: Int = 2
    /// When non-nil, tags are fitted dynamically to this pixel width using UIFont measurement.
    /// When nil, falls back to showing `maxTags` tags with a +N overflow pill.
    var availableTagWidth: CGFloat? = nil
    var maxTags: Int = 2

    @State private var thumbnail: UIImage?

    enum Style {
        case grid   // Rounded card with thumbnail
        case row    // Horizontal list row
    }

    var body: some View {
        Group {
            switch style {
            case .grid:  gridCard
            case .row:   rowCard
            }
        }
        .task(id: item.id) {
            guard thumbnail == nil, let data = item.thumbnailData else { return }
            let id = item.id
            let targetSize: CGSize = style == .grid
                ? CGSize(width: 200, height: 150)
                : CGSize(width: 48, height: 48)
            thumbnail = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.shared.image(for: id, data: data, targetSize: targetSize)
            }.value
        }
    }

    // MARK: - Grid card

    private var gridCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            // Thumbnail
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(item.fileType.tintColor.opacity(AppTheme.Tint.wash))
                .aspectRatio(4/3, contentMode: .fit)
                .overlay {
                    if let ui = thumbnail {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: item.fileType.sfSymbol)
                            .font(.system(size: AppTheme.IconSize.xLarge, weight: .light))
                            .foregroundStyle(item.fileType.tintColor)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 2) {
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.Colors.pinnedTint)
                        }
                        if item.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.favoriteTint)
                        }
                    }
                    .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if isSelectMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(isSelected ? AppTheme.Colors.accent : .white)
                            .shadow(radius: 1)
                            .padding(6)
                    }
                }

            // Info
            Text(item.title)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.label)
                .lineLimit(titleLines)

            // Tags with overflow pill — dynamic fit or fixed cap
            if !item.tags.isEmpty {
                let shown = availableTagWidth.map { fittingTagCount(item.tags, in: $0) } ?? min(maxTags, item.tags.count)
                let overflow = item.tags.count - shown
                HStack(spacing: AppTheme.Spacing.xSmall) {
                    ForEach(item.tags.prefix(shown)) { tag in
                        Text(tag.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(hex: tag.colorHex))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: tag.colorHex).opacity(AppTheme.Tint.wash))
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }
                    if overflow > 0 {
                        Text("+\(overflow)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.Colors.secondaryFill)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(AppTheme.Spacing.small)
        .background(AppTheme.Colors.secondaryBG)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        .shadow(color: AppTheme.Shadow.card.color,
                radius: AppTheme.Shadow.card.radius,
                x: AppTheme.Shadow.card.x,
                y: AppTheme.Shadow.card.y)
    }

    // MARK: - Dynamic tag fitting

    /// Returns how many tags from `tags` fit in `width` (in points), leaving room
    /// for a "+N" overflow pill when necessary.
    /// Uses UIFont measurement so results match what SwiftUI renders at the same size.
    private func fittingTagCount(_ tags: [Tag], in width: CGFloat) -> Int {
        let gap: CGFloat = AppTheme.Spacing.xSmall   // 4pt between pills
        let hPad: CGFloat = 12                        // 6pt left + 6pt right inside each pill
        let font = UIFont.systemFont(ofSize: 9, weight: .medium)

        func pillWidth(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width) + hPad
        }

        var used: CGFloat = 0
        var count = 0

        for i in 0..<tags.count {
            let tagW   = pillWidth(tags[i].name)
            let leadGap: CGFloat = count == 0 ? 0 : gap
            // How many would still overflow after including this tag?
            let remaining = tags.count - (count + 1)
            // Reserve space for the "+N" pill only if there will actually be leftovers
            let overflowW: CGFloat = remaining > 0 ? gap + pillWidth("+\(remaining)") : 0

            if used + leadGap + tagW + overflowW <= width {
                used += leadGap + tagW
                count += 1
            } else {
                break
            }
        }
        return count
    }

    // MARK: - Row card

    private var rowCard: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            // Checkbox in select mode
            if isSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.tertiaryLabel)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(item.fileType.tintColor.opacity(AppTheme.Tint.wash))
                    .frame(width: 48, height: 48)

                if let ui = thumbnail {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                } else {
                    Image(systemName: item.fileType.sfSymbol)
                        .font(.system(size: 20))
                        .foregroundStyle(item.fileType.tintColor)
                }
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.label)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .lineLimit(1)
                if !item.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.tags.prefix(3)) { tag in
                            Text(tag.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color(hex: tag.colorHex))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(hex: tag.colorHex).opacity(AppTheme.Tint.wash))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()

            // Trailing
            VStack(alignment: .trailing, spacing: 4) {
                SyncStatusBadge(status: item.syncStatus)
                HStack(spacing: 4) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.Colors.pinnedTint)
                    }
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.Colors.favoriteTint)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .animation(.easeInOut(duration: 0.2), value: isSelectMode)
        .background(isSelected ? AppTheme.Colors.accent.opacity(0.08) : AppTheme.Colors.flatCard)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
    }
}
