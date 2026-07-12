import SwiftUI

// MARK: - Card modifier

struct CardModifier: ViewModifier {
    var padding: CGFloat = AppTheme.Spacing.base

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.Colors.secondaryBG)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
            .shadow(
                color: AppTheme.Shadow.card.color,
                radius: AppTheme.Shadow.card.radius,
                x: AppTheme.Shadow.card.x,
                y: AppTheme.Shadow.card.y
            )
    }
}

extension View {
    func cardStyle(padding: CGFloat = AppTheme.Spacing.base) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: - Shimmer loading modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    var isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .overlay(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: phase - 0.3),
                            .init(color: .white.opacity(0.6), location: phase),
                            .init(color: .clear, location: phase + 0.3)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func shimmer(_ isActive: Bool = true) -> some View {
        modifier(ShimmerModifier(isActive: isActive))
    }
}

// MARK: - Redacted placeholder

extension View {
    func skeletonRedacted(_ condition: Bool) -> some View {
        self.redacted(reason: condition ? .placeholder : [])
    }
}

// MARK: - Conditional modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Navigation bar styling

extension View {
    func findlyNavigationStyle() -> some View {
        self
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppTheme.Colors.groupedBG, for: .navigationBar)
    }
}

// MARK: - Section header style

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTheme.Typography.title3)
                .foregroundStyle(AppTheme.Colors.label)
            Spacer()
            if let action {
                Button(actionLabel, action: action)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.accent)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.base)
    }
}

// MARK: - Empty state view

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let subtitle: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppTheme.Spacing.base) {
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
            VStack(spacing: AppTheme.Spacing.xSmall) {
                Text(title)
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                Text(subtitle)
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    .multilineTextAlignment(.center)
            }
            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppTheme.Spacing.xLarge)
                        .padding(.vertical, AppTheme.Spacing.medium)
                        .background(AppTheme.Colors.accent)
                        .clipShape(Capsule())
                }
                .padding(.top, AppTheme.Spacing.small)
            }
        }
        .padding(AppTheme.Spacing.xxLarge)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tag symbol view (handles SF Symbols and emojis)

struct TagSymbolView: View {
    let sfSymbol: String
    let color: Color
    let size: CGFloat

    private var isEmoji: Bool {
        !sfSymbol.unicodeScalars.allSatisfy { $0.value < 128 }
    }

    var body: some View {
        if isEmoji {
            Text(sfSymbol)
                .font(.system(size: size))
        } else {
            Image(systemName: sfSymbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Tag chip view

struct TagChipView: View {
    let tag: Tag
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: AppTheme.Spacing.xSmall) {
                TagSymbolView(
                    sfSymbol: tag.sfSymbol,
                    color: isSelected ? .white : Color(hex: tag.colorHex),
                    size: 11
                )
                Text(tag.name)
                    .font(AppTheme.Typography.caption1.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : Color(hex: tag.colorHex))
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.xSmall)
            .background(
                isSelected
                    ? Color(hex: tag.colorHex)
                    : Color(hex: tag.colorHex).opacity(0.15)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Animation.snappy, value: isSelected)
    }
}

// MARK: - Inline search bar

struct InlineSearchBar: View {
    @Binding var text: String
    var prompt: String = "Search..."
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                TextField(prompt, text: $text)
                    .focused(isFocused)
                    .onSubmit { onSubmit?() }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(AppTheme.Colors.tertiaryBG)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if isFocused.wrappedValue || !text.isEmpty {
                Button {
                    text = ""
                    isFocused.wrappedValue = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.base)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(AppTheme.Colors.groupedBG)
        .animation(.easeInOut(duration: 0.2), value: isFocused.wrappedValue)
    }
}

// MARK: - Sync status indicator

struct SyncStatusBadge: View {
    let status: SyncStatus
    /// When true, hides the badge entirely for .synced and .localOnly (non-notable states).
    var compactMode: Bool = false

    var body: some View {
        if compactMode && (status == .synced || status == .localOnly) {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                if status == .syncing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(status.tintColor)
                } else {
                    Image(systemName: status.sfSymbol)
                        .font(.caption2)
                        .foregroundStyle(status.tintColor)
                        .accessibilityLabel(status.displayLabel)
                        .accessibilityHidden(false)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
