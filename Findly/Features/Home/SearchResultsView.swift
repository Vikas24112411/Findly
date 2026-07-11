import SwiftUI

struct SearchResultsView: View {

    let results: [Item]
    let isLoading: Bool
    let query: String
    var onOpen: (Item) -> Void

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
                    HStack {
                        Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.base)
                    .padding(.top, AppTheme.Spacing.small)

                    ForEach(results) { item in
                        NavigationLink(destination: ItemDetailView(item: item)
                            .onAppear { onOpen(item) }
                        ) {
                            ItemCardView(item: item, style: .row)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppTheme.Spacing.base)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.small)
            }
        }
    }
}
