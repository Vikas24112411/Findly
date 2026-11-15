import SwiftUI

// Scrolling header: one title that morphs from the 34pt large title into a 17pt
// title on a glass pill in the navigation bar. The motion spec is the approved
// mockup, Design/header-transition-final.html (mixCurve, renderGlide2, mixUpdate).

// MARK: - Curve maths

enum HeaderTransition {
    /// Scroll distance over which the forward glide completes.
    static let dockDistance: CGFloat = 170
    /// Pace of the first part of the glide (R1).
    static let leadDistance: CGFloat = 110
    /// Once docked, the title stays docked until the offset drops below this.
    static let reverseThreshold: CGFloat = 44
    static let reverseDuration: TimeInterval = 0.5

    /// Space the large title takes in scroll content: 4 above, a 41pt line, 12 below.
    static let largeTitleSpace: CGFloat = 57
    /// Large title centre, measured down from the bottom of the navigation bar.
    static let largeTitleCentre: CGFloat = 24.5
    /// Navigation bar centre, measured up from its bottom edge.
    static let navBarHalfHeight: CGFloat = 22
    static let pillHeight: CGFloat = 36
    static let pillPadding: CGFloat = 36
    static let dockedScale: CGFloat = 0.5

    static func clamp(_ x: CGFloat) -> CGFloat { min(1, max(0, x)) }
    static func smoothstep(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// A soft maximum: follows `a` while it is well above `b`, then eases onto `b`.
    static func smoothMax(_ a: CGFloat, _ b: CGFloat, k: CGFloat) -> CGFloat {
        (a + b + sqrt((a - b) * (a - b) + k * k)) / 2
    }

    /// Scrubbed progress: starts at R1's pace and lands slowly like R2.
    static func progress(at y: CGFloat) -> CGFloat {
        let r1 = smoothstep(clamp(y / leadDistance))
        let r2 = smoothstep(clamp(y / dockDistance))
        return lerp(r1, r2, r2)
    }

    /// The only value taken from scroll geometry: clamped to the range the header
    /// reacts to and rounded to half points, so nothing is emitted past the dock
    /// distance.
    static func quantise(_ rawOffset: CGFloat) -> CGFloat {
        let clamped = min(dockDistance, max(-400, rawOffset))
        return (clamped * 2).rounded() / 2
    }
}

// MARK: - State machine

/// Owns the header's scroll state. It lives next to the header, and only the
/// header layer reads it, so scrolling never invalidates a tab's body.
@Observable
@MainActor
final class HeaderTransitionModel {
    private enum Mode { case scrub, docked, returning }

    /// Quantised scroll offset, in -400...170.
    private(set) var offset: CGFloat = 0
    /// 0 = large title, 1 = docked on the pill.
    private(set) var progress: CGFloat = 0
    /// Incremented each time the title lands, to trigger the pill's settle.
    private(set) var landings = 0
    /// Past the reverse threshold. Drives the Reduce Motion crossfade.
    private(set) var isPastThreshold = false
    /// Vertical centre of the navigation bar's items, in global coordinates,
    /// measured from the bar itself so the pill lines up with the bar buttons.
    var barItemCentreY: CGFloat?

    @ObservationIgnored private var mode = Mode.scrub
    // Scrubbing is rescaled so it passes through (anchorOffset, anchorProgress).
    @ObservationIgnored private var anchorOffset: CGFloat = 0
    @ObservationIgnored private var anchorProgress: CGFloat = 0

    func scroll(to y: CGFloat) {
        offset = y
        let past = y >= HeaderTransition.reverseThreshold
        if past != isPastThreshold { isPastThreshold = past }

        if y < 2 {
            anchorOffset = 0
            anchorProgress = 0
        }

        switch mode {
        case .scrub:
            let next = scrubbedProgress(at: y)
            if next >= 0.999 {
                progress = 1
                mode = .docked
                landings += 1
            } else if next != progress {
                progress = next
            }
        case .docked:
            if y < HeaderTransition.reverseThreshold { beginReturn() }
        case .returning:
            break
        }
    }

    private func scrubbedProgress(at y: CGFloat) -> CGFloat {
        let m = HeaderTransition.progress(at: y)
        let m0 = HeaderTransition.progress(at: anchorOffset)
        if y <= anchorOffset {
            return m0 > 0 ? anchorProgress * m / m0 : 0
        }
        let remaining = 1 - m0
        guard remaining > 0.0001 else { return 1 }
        return anchorProgress + (m - m0) * (1 - anchorProgress) / remaining
    }

    /// The return to the large title plays by itself, with no overshoot.
    private func beginReturn() {
        mode = .returning
        // Cubic ease-out, as in the mockup.
        withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: HeaderTransition.reverseDuration)) {
            progress = 0
        } completion: { [weak self] in
            self?.finishReturn()
        }
    }

    private func finishReturn() {
        guard mode == .returning else { return }
        mode = .scrub
        // Resume scrubbing from where the scroll view is now. The anchor is kept
        // at or below the threshold so the glide can still complete if the user
        // scrolled far back down while the return was playing.
        anchorOffset = max(0, min(offset, HeaderTransition.reverseThreshold))
        anchorProgress = 0
        let next = scrubbedProgress(at: offset)
        guard next > 0.001 else { return }
        withAnimation(.smooth(duration: 0.35)) {
            progress = next >= 0.999 ? 1 : next
        }
        if next >= 0.999 {
            mode = .docked
            landings += 1
        }
    }
}

// MARK: - Space for the large title in scroll content

/// Reserves the room the large title occupies at rest. The title itself is drawn
/// by the header layer, above the scroll content.
struct LargeTitleSpace: View {
    var body: some View {
        Color.clear
            .frame(height: HeaderTransition.largeTitleSpace)
            .accessibilityHidden(true)
    }
}

// MARK: - Header layer

/// Reads the model, so it is the only view that updates while scrolling.
private struct GlassPillHeaderOverlay: View {
    let model: HeaderTransitionModel
    let title: String
    let forceDocked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The reader stays inside the safe area to learn where the navigation bar
        // ends; the layer inside it then draws from the top of the screen.
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            // The layer's origin is the reader's origin moved up by the safe area.
            let layerOriginY = proxy.frame(in: .global).minY - safeTop
            let navCentre = model.barItemCentreY.map { $0 - layerOriginY }
                ?? safeTop - HeaderTransition.navBarHalfHeight
            let largeCentre = safeTop + HeaderTransition.largeTitleCentre
            ZStack {
                if #unavailable(iOS 26) {
                    ScrollEdgeFade(height: safeTop + 22)
                        .opacity(HeaderTransition.clamp(model.offset / 40))
                }
                if reduceMotion {
                    CrossfadeHeaderLayer(
                        title: title,
                        isDocked: forceDocked || model.isPastThreshold,
                        largeCentreY: largeCentre - model.offset,
                        navCentreY: navCentre,
                        width: proxy.size.width
                    )
                } else {
                    GlideHeaderLayer(
                        progress: model.progress,
                        forced: forceDocked ? 1 : 0,
                        offset: model.offset,
                        title: title,
                        largeCentreY: largeCentre,
                        navCentreY: navCentre,
                        width: proxy.size.width,
                        landings: model.landings + (forceDocked ? 1 : 0)
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height + safeTop, alignment: .top)
            .ignoresSafeArea(.container, edges: .top)
        }
        .animation(.smooth(duration: 0.35), value: forceDocked)
        .allowsHitTesting(false)
    }
}

/// The morphing title and its pill. `progress` and `forced` are animatable, so the
/// timed return and the select-mode dock interpolate along the same path as the
/// scrubbed glide.
private struct GlideHeaderLayer: View, Animatable {
    var progress: CGFloat
    var forced: CGFloat
    let offset: CGFloat
    let title: String
    let largeCentreY: CGFloat
    let navCentreY: CGFloat
    let width: CGFloat
    let landings: Int

    @State private var titleWidth: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, forced) }
        set {
            progress = newValue.first
            forced = newValue.second
        }
    }

    var body: some View {
        let a = HeaderTransition.lerp(progress, 1, forced)
        let scale = HeaderTransition.lerp(1, HeaderTransition.dockedScale, a)
        let scaledWidth = titleWidth * scale
        let leading = HeaderTransition.lerp(AppTheme.Spacing.base, (width - scaledWidth) / 2, a)
        // Centre-anchored, so the title never rises and then falls back.
        let scrolledCentre = HeaderTransition.smoothMax(largeCentreY - offset, navCentreY, k: 10)
        let centreY = HeaderTransition.lerp(scrolledCentre, navCentreY, forced)

        ZStack {
            HeaderPill(landings: landings)
                .frame(
                    width: titleWidth * HeaderTransition.dockedScale + HeaderTransition.pillPadding,
                    height: HeaderTransition.pillHeight
                )
                .scaleEffect(HeaderTransition.lerp(0.72, 1, a))
                .opacity(HeaderTransition.clamp((a - 0.5) / 0.5))
                .position(x: width / 2, y: navCentreY)

            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppTheme.Colors.label)
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleWidth = $0 }
                .scaleEffect(scale)
                .position(x: leading + scaledWidth / 2, y: centreY)
                .opacity(titleWidth > 0 ? 1 : 0)
                .accessibilityAddTraits(.isHeader)
        }
        // This body already runs once per animated frame with interpolated values;
        // the modifiers inside must not animate a second time.
        .transaction { $0.animation = nil }
    }
}

/// Reduce Motion: the large title scrolls away with the content and the small
/// title crossfades in, with no glide and no settle.
private struct CrossfadeHeaderLayer: View {
    let title: String
    let isDocked: Bool
    let largeCentreY: CGFloat
    let navCentreY: CGFloat
    let width: CGFloat

    @State private var smallWidth: CGFloat = 0

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppTheme.Colors.label)
                .lineLimit(1)
                .frame(width: max(0, width - AppTheme.Spacing.base * 2), alignment: .leading)
                .position(x: width / 2, y: largeCentreY)
                .opacity(isDocked ? 0 : 1)
                .accessibilityHidden(isDocked)

            Group {
                HeaderPill(landings: 0)
                    .frame(width: smallWidth + HeaderTransition.pillPadding, height: HeaderTransition.pillHeight)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.label)
                    .lineLimit(1)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { smallWidth = $0 }
                    .accessibilityHidden(!isDocked)
            }
            .position(x: width / 2, y: navCentreY)
            .opacity(isDocked ? 1 : 0)
        }
        .accessibilityAddTraits(.isHeader)
        .animation(.easeInOut(duration: 0.2), value: isDocked)
    }
}

/// The Liquid Glass capsule behind the docked title, with a small settle each
/// time the title lands.
private struct HeaderPill: View {
    let landings: Int

    var body: some View {
        glass
            .keyframeAnimator(initialValue: 1.0, trigger: landings) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.06, duration: 0.15, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.23, spring: .bouncy)
            }
    }

    @ViewBuilder
    private var glass: some View {
        if #available(iOS 26, *) {
            Color.clear.glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.1), radius: 9, y: 6)
        }
    }
}

/// Before iOS 26 there is no system scroll edge effect, so the header draws its own.
private struct ScrollEdgeFade: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Modifier

/// Apply to the tab's `ScrollView`. Put `LargeTitleSpace()` first in its content.
struct GlassPillHeaderModifier: ViewModifier {
    let title: String
    let forceDocked: Bool

    // Kept here rather than in the tab's root view; this body never reads it.
    @State private var model = HeaderTransitionModel()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                HeaderTransition.quantise(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { [model] _, offset in
                model.scroll(to: offset)
            }
            .overlay {
                GlassPillHeaderOverlay(model: model, title: title, forceDocked: forceDocked)
            }
            .navigationBarTitleDisplayMode(.inline)
            // An empty principal item keeps the navigation bar at full height on
            // tabs that have no other toolbar items, and reports where the bar
            // centres its items so the pill sits level with the bar buttons.
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            (geometry.frame(in: .global).midY * 2).rounded() / 2
                        } action: { [model] centre in
                            model.barItemCentreY = centre
                        }
                        .accessibilityHidden(true)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

extension View {
    /// The scrolling header: a large title that morphs into a glass pill in the
    /// navigation bar. `forceDocked` holds the docked title regardless of scroll
    /// position, for modes such as multi-select.
    func glassPillHeader(_ title: String, forceDocked: Bool = false) -> some View {
        modifier(GlassPillHeaderModifier(title: title, forceDocked: forceDocked))
    }
}
