import SwiftUI

/// Floating action button with two interactions:
/// - Short tap  → opens the add-item sheet
/// - Long press (250 ms) → opens the radial menu; the user can then drag to an option and release to select it.
///
/// Touches come from a UIKit recogniser (`FABTouchSurface`) + a manual 250 ms timer to detect long-press.
/// A SwiftUI `DragGesture(minimumDistance: 0)` here only receives its first event ~750 ms after
/// touch-down (measured on device), which made the hold feel close to a second long.
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
        .overlay(
            FABTouchSurface(
                onBegan: { _ in
                    isPressed = true

                    // Start the 250 ms long-press timer.
                    // Uses .common RunLoop mode so it fires even while the RunLoop is in
                    // .tracking mode (during scroll) or under brief main-thread load.
                    longPressTimer?.invalidate()
                    longPressConsumed = false
                    let t = Timer(timeInterval: 0.25, repeats: false) { _ in
                        DispatchQueue.main.async {
                            longPressConsumed = true
                            HapticFeedback.medium()
                            onLongPress?()
                        }
                    }
                    RunLoop.main.add(t, forMode: .common)
                    longPressTimer = t
                },
                onChanged: { location in
                    // Once long press has fired, forward drag location.
                    if longPressConsumed {
                        onDragChanged?(location)
                    }
                },
                onEnded: { location, cancelled in
                    isPressed = false
                    longPressTimer?.invalidate()
                    longPressTimer = nil

                    if longPressConsumed {
                        // Finger lifted after long press — report final drag position.
                        onDragEnded?(location)
                        longPressConsumed = false
                    } else if !cancelled {
                        // Finger lifted before the long press fired — treat as a tap.
                        HapticFeedback.medium()
                        showSheet = true
                    }
                }
            )
            .clipShape(Circle())
        )
        .onDisappear {
            longPressTimer?.invalidate()
            longPressTimer = nil
            longPressConsumed = false
            isPressed = false
        }
        .accessibilityLabel("Add item")
    }
}

// MARK: - Touch surface

/// Transparent UIKit view that reports touch-down, movement and lift immediately,
/// in window coordinates (matches SwiftUI's `.global` space for the root view).
private struct FABTouchSurface: UIViewRepresentable {
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    /// Second argument is true when the system cancelled the touch.
    var onEnded: (CGPoint, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handle(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: FABTouchSurface
        init(_ parent: FABTouchSurface) { self.parent = parent }

        @objc func handle(_ press: UILongPressGestureRecognizer) {
            let location = press.location(in: nil)
            switch press.state {
            case .began:     parent.onBegan(location)
            case .changed:   parent.onChanged(location)
            case .ended:     parent.onEnded(location, false)
            case .cancelled, .failed: parent.onEnded(location, true)
            default: break
            }
        }
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
