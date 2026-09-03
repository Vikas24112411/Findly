import SwiftUI

/// Horizontal scrolling row of item cards.
struct RecentItemsSection: View {

    let title: String
    let items: [Item]
    var onOpen: (Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppTheme.Spacing.medium) {
                    ForEach(items) { item in
                        Button { onOpen(item) } label: {
                            RecentItemCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
            }
        }
    }
}

// MARK: - Card

private struct RecentItemCard: View {

    let item: Item
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            // Thumbnail or type icon
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(item.fileType.tintColor.opacity(0.12))
                    .frame(width: 140, height: 100)

                if let uiImage = thumbnail {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
                } else {
                    Image(systemName: item.fileType.sfSymbol)
                        .font(.system(size: AppTheme.IconSize.xLarge))
                        .foregroundStyle(item.fileType.tintColor)
                }
            }

            // Title
            Text(item.title)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.label)
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)

            // Meta
            HStack {
                Text(item.createdAt.shortRelativeString)
                    .font(AppTheme.Typography.caption2)
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                Spacer()
                SyncStatusBadge(status: item.syncStatus)
            }
            .frame(width: 140)
        }
        .task(id: item.id) {
            guard thumbnail == nil, let data = item.thumbnailData else { return }
            let id = item.id
            thumbnail = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.shared.image(for: id, data: data, targetSize: CGSize(width: 140, height: 100))
            }.value
        }
    }
}
