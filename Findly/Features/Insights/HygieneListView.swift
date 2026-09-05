import SwiftUI

/// Drill-down list for a Hygiene trio category (Untagged / Never opened / Stale).
/// Rows mirror the Most Opened style; tapping a file opens the viewer.
struct HygieneListView: View {

    @Environment(FileViewerCoordinator.self) private var fileViewer

    let title: String
    let items: [Item]
    let totalCount: Int

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if totalCount > items.count {
                    Text("Showing \(items.count) of \(totalCount)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Spacing.base)
                        .padding(.vertical, AppTheme.Spacing.small)
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { fileViewer.open(item) } label: {
                            HStack(spacing: AppTheme.Spacing.medium) {
                                Image(systemName: item.fileType.sfSymbol)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(item.fileType.tintColor)
                                    .frame(width: 30, height: 30)
                                    .background(item.fileType.tintColor.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(AppTheme.Typography.subheadline)
                                        .foregroundStyle(AppTheme.Colors.label)
                                        .lineLimit(1)
                                    Text(item.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.base)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(AppTheme.Colors.secondaryBG)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                .padding(.horizontal, AppTheme.Spacing.base)
                .padding(.bottom, AppTheme.Spacing.large)
            }
        }
        .background(AppTheme.Colors.groupedBG)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
