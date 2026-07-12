import SwiftUI

// MARK: - Progress helper

func scrollProgress(from offset: CGFloat, over distance: CGFloat = 55.0) -> CGFloat {
    min(1.0, max(0.0, offset / distance))
}

// MARK: - Large title in scroll content

struct LargeTitleHeader: View {
    let title: String
    let progress: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(AppTheme.Colors.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.base)
            .padding(.top, AppTheme.Spacing.small)
            .padding(.bottom, AppTheme.Spacing.medium)
            .opacity(1.0 - progress)
    }
}

// MARK: - Scroll offset tracker

struct ScrollOffsetModifier: ViewModifier {
    @Binding var scrollOffset: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newValue in
                    scrollOffset = max(0, newValue)
                }
        } else {
            content
        }
    }
}

// MARK: - Nav bar transition modifier

struct NavTransitionTitleModifier: ViewModifier {
    let title: String
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.label)
                        .opacity(progress)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(progress > 0.18 ? .visible : .hidden, for: .navigationBar)
    }
}

// MARK: - View extensions

extension View {
    func trackScrollOffset(_ offset: Binding<CGFloat>) -> some View {
        modifier(ScrollOffsetModifier(scrollOffset: offset))
    }

    func navTransitionTitle(_ title: String, progress: CGFloat) -> some View {
        modifier(NavTransitionTitleModifier(title: title, progress: progress))
    }
}
