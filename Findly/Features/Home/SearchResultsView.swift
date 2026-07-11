import SwiftUI

struct SearchResultsView: View {

    let results: [Item]
    let isLoading: Bool
    let query: String
    var activeFileTypes: Set<FileType> = []
    var isSelectMode: Bool = false
    var selectedIDs: Set<UUID> = []
    var onOpen: (Item) -> Void
    var onToggleSelect: (Item) -> Void = { _ in }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppTheme.Spacing.xxxLarge)
            } else if results.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "No results",
                    subtitle: "Nothing in your vault matches \"\(query)\"."
                )
                .padding(.top, AppTheme.Spacing.xxxLarge)
            } else {
                LazyVStack(spacing: AppTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                        HStack {
                            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            Spacer()
                        }
                        if !activeFileTypes.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppTheme.Spacing.xSmall) {
                                    ForEach(Array(activeFileTypes), id: \.self) { type in
                                        Label(type.displayName, systemImage: type.sfSymbol)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(type.tintColor)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(type.tintColor.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.base)
                    .padding(.top, AppTheme.Spacing.small)

                    ForEach(results) { item in
                        let isSelected = selectedIDs.contains(item.id)
                        if isSelectMode {
                            ItemCardView(item: item, style: .row, isSelectMode: true, isSelected: isSelected)
                                .onTapGesture { onToggleSelect(item) }
                                .padding(.horizontal, AppTheme.Spacing.base)
                        } else {
                            NavigationLink(destination: ItemDetailView(item: item)
                                .onAppear { onOpen(item) }
                            ) {
                                ItemCardView(item: item, style: .row)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, AppTheme.Spacing.base)
                        }
                    }
                }
                .padding(.vertical, AppTheme.Spacing.small)
            }
        }
    }
}
