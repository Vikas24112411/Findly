import SwiftUI

/// Floating action button that reveals the add-item sheet.
struct FABView: View {

    @Binding var showSheet: Bool
    @State private var isPressed = false

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            showSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent)
                    .frame(width: 56, height: 56)
                    .shadow(color: AppTheme.Shadow.fab.color,
                            radius: AppTheme.Shadow.fab.radius,
                            x: AppTheme.Shadow.fab.x,
                            y: AppTheme.Shadow.fab.y)

                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(FABButtonStyle())
    }
}

// MARK: - Button style with spring press feedback

private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(AppTheme.Animation.snappy, value: configuration.isPressed)
    }
}
