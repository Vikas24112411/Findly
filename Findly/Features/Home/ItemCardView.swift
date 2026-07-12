import SwiftUI

/// Reusable item card that supports grid and row display styles.
struct ItemCardView: View {

    let item: Item
    var style: Style = .grid
    var isSelectMode: Bool = false
    var isSelected: Bool = false

    enum Style {
        case grid   // Rounded card with thumbnail
        case row    // Horizontal list row
    }

    var body: some View {
        switch style {
        case .grid:  gridCard
        case .row:   rowCard
        }
    }

    // MARK: - Grid card

    private var gridCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            // Thumbnail
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(item.fileType.tintColor.opacity(0.10))
                .aspectRatio(4/3, contentMode: .fit)
                .overlay {
                    if let data = item.thumbnailData, let ui = UIImage(data: data) {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.label)
                    .lineLimit(2)
                HStack {
                    Text(item.fileSize.fileSizeString)
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    Spacer()
                    SyncStatusBadge(status: item.syncStatus)
                }
            }

            // Tags (up to 2)
            if !item.tags.isEmpty {
                HStack(spacing: AppTheme.Spacing.xSmall) {
                    ForEach(item.tags.prefix(2)) { tag in
                        Text(tag.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(hex: tag.colorHex))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: tag.colorHex).opacity(0.12))
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
                    .fill(item.fileType.tintColor.opacity(0.12))
                    .frame(width: 48, height: 48)

                if let data = item.thumbnailData, let ui = UIImage(data: data) {
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
                                .background(Color(hex: tag.colorHex).opacity(0.12))
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
        .background(isSelected ? AppTheme.Colors.accent.opacity(0.08) : AppTheme.Colors.secondaryBG)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        .shadow(color: AppTheme.Shadow.card.color,
                radius: AppTheme.Shadow.card.radius,
                x: AppTheme.Shadow.card.x,
                y: AppTheme.Shadow.card.y)
    }
}
