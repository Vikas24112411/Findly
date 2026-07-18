import SwiftUI

/// Floating action button with two interactions:
/// - Short tap  → opens the add-item sheet
/// - Long press (400 ms) → opens the radial menu; the user can then drag to an option and release to select it.
///
/// Uses a single `DragGesture(minimumDistance: 0)` + a manual 400 ms timer to detect long-press.
/// This is more reliable than `LongPressGesture.sequenced(before: DragGesture)`, which can fail
/// when the finger moves slightly during the hold.
struct FABView: View {

    @Binding var showSheet: Bool
    var isRadialOpen: Bool = false
    var onLongPress: (() -> Void)? = nil
    /// Called continuously while dragging after the long press fires (global coords).
    var onDragChanged: ((CGPoint) -> Void)? = nil
    /// Called when the finger lifts after a long-press drag (global coords).
    var onDragEnded: ((CGPoint) -> Void)? = nil

    @State private var isPressed = false
    @State private var longPressConsumed = false
    @State private var longPressTimer: Timer? = nil

    var body: some View {
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
                .rotationEffect(.degrees(isRadialOpen ? 45 : 0))
                .animation(AppTheme.Animation.snappy, value: isRadialOpen)
        }
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(AppTheme.Animation.snappy, value: isPressed)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if !isPressed { isPressed = true }

                    // Start the 400 ms long-press timer on first event.
                    if longPressTimer == nil && !longPressConsumed {
                        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                            DispatchQueue.main.async {
                                longPressConsumed = true
                                HapticFeedback.medium()
                                onLongPress?()
                            }
                        }
                    }

                    // Once long press has fired, forward drag location.
                    if longPressConsumed {
                        onDragChanged?(value.location)
                    }
                }
                .onEnded { value in
                    isPressed = false
                    longPressTimer?.invalidate()
                    longPressTimer = nil

                    if longPressConsumed {
                        // Finger lifted after long press — report final drag position.
                        onDragEnded?(value.location)
                        longPressConsumed = false
                    } else {
                        // Finger lifted before 500 ms — treat as a tap.
                        HapticFeedback.medium()
                        showSheet = true
                    }
                }
        )
        .accessibilityLabel("Add item")
    }
}

// MARK: - Button style (used by the Search FAB in ContentView)

struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(AppTheme.Animation.snappy, value: configuration.isPressed)
    }
}
