import SwiftUI
import SwiftData
import QuickLook
import AVFoundation
import PDFKit

@Observable
@MainActor
final class FileViewerCoordinator {
    var selectedItem: Item?

    func open(_ item: Item) {
        guard item.isAvailableForPresentation else { return }
        selectedItem = item
    }

    func close() {
        selectedItem = nil
    }
}

enum FileResolutionStrategy: Equatable {
    case useLocalFile
    case recoverFromDrive
    case unavailable

    static func choose(hasLocalFile: Bool, hasRemoteFile: Bool) -> Self {
        if hasLocalFile { return .useLocalFile }
        if hasRemoteFile { return .recoverFromDrive }
        return .unavailable
    }
}

struct FileOpenSession {
    private(set) var hasRecordedOpen = false

    @discardableResult
    mutating func recordOpen(for item: Item) -> Bool {
        guard !hasRecordedOpen else { return false }
        hasRecordedOpen = true
        item.markOpened()
        return true
    }
}

enum NotePreviewLoader {
    static func supports(fileType: FileType, originalFileName: String) -> Bool {
        fileType == .note && (originalFileName as NSString).pathExtension.lowercased() == "txt"
    }

    static func load(url: URL) async throws -> String {
        let text = try await Task.detached(priority: .userInitiated) {
            try String(contentsOf: url, encoding: .utf8)
        }.value
        try Task.checkCancellation()
        return text
    }
}

struct FileViewerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @Environment(FileViewerCoordinator.self) private var viewerCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    let item: Item
    @ScaledMetric(relativeTo: .headline) private var headerControlHeight: CGFloat = 44

    @State private var previewURL: URL?
    @State private var noteText: String?
    @State private var isResolving = false
    @State private var resolutionError: String?
    @State private var controlsVisible = true
    @State private var showInspector = false
    @State private var inspectorDetent: PresentationDetent = .fraction(0.40)
    @State private var shareURL: URL?
    @State private var showDeleteConfirm = false
    @State private var deleteError: Error?
    @State private var isDeleting = false
    @State private var openSession = FileOpenSession()
    @State private var mediaController = MediaPlayerController()
    @State private var dismissDragOffset: CGFloat = 0
    @State private var imageZoomed = false

    var body: some View {
        if item.isAvailableForPresentation {
            content
        }
    }

    private var content: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                previewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .offset(y: dismissDragOffset)
                    .gesture(PreviewContentTapGesture(isEnabled: contentTapEnabled, onTap: handleContentTap))
                    .simultaneousGesture(dismissDragGesture)
                // Info panel layers BETWEEN the preview and the toolbar:
                // preview (back) -> inspector panel -> toolbar (front, single
                // instance). No duplicate toolbar is re-rendered inside the
                // panel; the shared bottomChrome stays on top.
                if showInspector {
                    inspectorPanel(
                        containerHeight: geometry.size.height,
                        bottomInset: geometry.safeAreaInsets.bottom
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
                }
                // Photos-style bottom chrome: the slim scrubber is stacked above
                // the Findly toolbar with a fixed gap, so the two can never
                // overlap. Both hide/show together via the shared chrome toggle.
                // Stays mounted while the inspector is open (forced visible via
                // chromeVisible), so opening info never hides/re-creates it.
                bottomChrome
                    .opacity((chromeVisible ? 1 : 0) * dragFade)
                    .allowsHitTesting(chromeVisible)
                    .accessibilityHidden(!chromeVisible)
                    .zIndex(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) {
            FilePreviewHeader(title: item.title, controlHeight: headerControlHeight, isDeleting: isDeleting) {
                viewerCoordinator.close()
            }
            .opacity((chromeVisible ? 1 : 0) * dragFade)
            .allowsHitTesting(chromeVisible)
            .accessibilityHidden(!chromeVisible)
        }
        // Immersive black only behind the Quick Look fallback, whose native
        // viewer is black. Local viewers (image/video/audio/PDF) paint their
        // own fullscreen themed backgrounds, so the container stays themed
        // for them — including loading / error / note states.
        .background(
            (usesImmersiveBlackBackdrop
                ? Color.black
                : AppTheme.Colors.background).ignoresSafeArea()
        )
        .statusBarHidden()
        .task(id: item.id) {
            controlsVisible = true
            imageZoomed = false
            dismissDragOffset = 0
            await resolveFile()
        }
        .modifier(actionPresentations(isActive: true))
    }

    /// Inline metadata panel pinned between the preview content and the
    /// floating toolbar (preview -> panel -> toolbar in z-order). Single
    /// toolbar instance in bottomChrome stays on top, so nothing is
    /// re-rendered inside the panel.
    private func inspectorPanel(containerHeight: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            // System-sheet-style grabber; doubles as the drag handle for
            // detent changes (40% <-> 60%) and swipe-down-to-dismiss.
            Capsule()
                .fill(AppTheme.Colors.tertiaryLabel)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .accessibilityLabel("File info panel handle")
                .gesture(inspectorDragGesture)
            // Custom title (instead of a NavigationBar) so the whole panel
            // shares one grouped background with no white bar seam.
            Text("File Info")
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.label)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            MetadataInspectorView(
                item: item,
                resolvedURL: previewURL,
                selectedDetent: $inspectorDetent,
                isDeleting: isDeleting,
                onRetry: { Task { await resolveFile() } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        // Taller by the home-indicator inset and shifted down by the same
        // amount, so the gray reaches the screen edge instead of stopping at
        // the safe-area boundary (which left a white strip). Plain
        // background + clip paint the full frame — including the grabber and
        // title band, which a safe-area-expanding background shape left
        // transparent (white preview showing through in light mode).
        .frame(height: inspectorHeight(containerHeight: containerHeight) + bottomInset)
        .background(AppTheme.Colors.groupedBG)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 16, y: -4)
        .offset(y: bottomInset)
        .animation(reduceMotion ? nil : AppTheme.Animation.inspector, value: inspectorDetent)
    }

    private func inspectorHeight(containerHeight: CGFloat) -> CGFloat {
        let fraction: CGFloat = inspectorDetent == .fraction(0.60) ? 0.60 : 0.40
        return containerHeight * fraction
    }

    /// Grabber drag: up expands 40% -> 60%, down collapses 60% -> 40%,
    /// further down from 40% dismisses. Disabled while deleting.
    private var inspectorDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard !isDeleting else { return }
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                guard abs(vertical) > 16, abs(vertical) > horizontal else { return }
                if vertical < 0 {
                    // Swipe up always expands to 60%.
                    guard inspectorDetent != .fraction(0.60) else { return }
                    withAnimation(reduceMotion ? nil : AppTheme.Animation.inspector) {
                        inspectorDetent = .fraction(0.60)
                    }
                } else {
                    if inspectorDetent == .fraction(0.60) {
                        // First swipe down collapses to 40%; a long swipe
                        // dismisses straight away.
                        withAnimation(reduceMotion ? nil : AppTheme.Animation.inspector) {
                            inspectorDetent = vertical > 120 ? .fraction(0.40) : .fraction(0.40)
                        }
                        if vertical > 160 {
                            setInspectorVisible(false)
                        }
                    } else {
                        guard vertical > 60 else { return }
                        setInspectorVisible(false)
                    }
                }
            }
    }

    private var canToggleControls: Bool {
        previewURL != nil && !isResolving && resolutionError == nil &&
        !showInspector && shareURL == nil && !showDeleteConfirm &&
        deleteError == nil && !isDeleting && !voiceOverEnabled
    }

    private var chromeVisible: Bool {
        controlsVisible || !canToggleControls
    }

    /// Whether a tap on the preview content reaches us at all. True while the
    /// chrome can toggle, or while the inspector is open (tap dismisses it).
    /// VoiceOver stays excluded from toggling but included for dismissing, so
    /// the panel closes for everyone.
    private var contentTapEnabled: Bool {
        (canToggleControls || showInspector) && (noteText != nil || previewURL != nil)
    }

    private func handleContentTap() {
        // Third way to close the inspector (besides the info icon and drag):
        // tapping the background preview dismisses the panel. Never toggles
        // the chrome at the same time, and never while a share sheet,
        // delete confirmation, or delete error is up.
        if showInspector {
            guard shareURL == nil && !showDeleteConfirm && deleteError == nil else { return }
            setInspectorVisible(false)
            return
        }
        toggleControls()
    }

    private func toggleControls() {
        guard canToggleControls else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            controlsVisible.toggle()
        }
    }

    /// Photos-style drag-down-to-close. Only for image/video/audio: notes,
    /// PDFs, and Quick Look documents scroll vertically, and a dismiss drag
    /// there would fire while the user is just scrolling. Disabled while the
    /// image is zoomed (drags pan the zoomed photo then), while the inspector
    /// is open, and whenever the chrome cannot toggle (share/delete flows).
    private var dismissDragEnabled: Bool {
        canToggleControls && isVisualMedia && (item.fileType != .image || !imageZoomed)
    }

    private var isVisualMedia: Bool {
        (item.fileType == .image || item.fileType == .video || item.fileType == .audio) &&
        previewURL != nil && !isResolving && resolutionError == nil && noteText == nil
    }

    /// Chrome fades as the content is pulled down, like Photos.
    private var dragFade: Double {
        DismissDragEvaluator.fade(for: dismissDragOffset)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: DismissDragEvaluator.minimumDistance)
            .onChanged { value in
                guard dismissDragEnabled else { return }
                dismissDragOffset = DismissDragEvaluator.offset(for: value.translation)
            }
            .onEnded { value in
                guard dismissDragEnabled,
                      DismissDragEvaluator.shouldDismiss(translation: value.translation) else {
                    guard dismissDragOffset != 0 else { return }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                        dismissDragOffset = 0
                    }
                    return
                }
                dismissDragOffset = 0
                HapticFeedback.medium()
                viewerCoordinator.close()
            }
    }

    private func actionPresentations(isActive: Bool) -> FileActionPresentations {
        FileActionPresentations(
            isActive: isActive,
            shareURL: $shareURL,
            showDeleteConfirm: $showDeleteConfirm,
            deleteError: $deleteError,
            onDelete: deleteItem
        )
    }

    /// True while a video/audio URL is on screen. The scrubber only exists
    /// in this state, so it can never appear over notes, images, or PDFs.
    private var isMediaPreview: Bool {
        (item.fileType == .video || item.fileType == .audio) &&
        previewURL != nil && !isResolving && resolutionError == nil && noteText == nil
    }

    /// Black backdrop only for the Quick Look fallback path (other document
    /// types); every local viewer paints its own themed background.
    private var usesImmersiveBlackBackdrop: Bool {
        previewURL != nil && noteText == nil && resolutionError == nil && !isResolving &&
        item.fileType != .image && item.fileType != .video &&
        item.fileType != .audio && item.fileType != .pdf
    }

    private var bottomChrome: some View {
        VStack(spacing: 8) {
            if isMediaPreview {
                MediaScrubberView(controller: mediaController)
                    .padding(.horizontal, 16)
            }
            floatingToolbar
        }
    }

    private var floatingToolbar: some View {
        FilePreviewToolbar(
            isFavorite: item.isFavorite,
            isPinned: item.isPinned,
            isInspectorVisible: showInspector,
            canShare: previewURL != nil && !isResolving,
            isDeleting: isDeleting,
            onShare: { shareURL = previewURL },
            onFavorite: {
                item.isFavorite.toggle()
                saveWithHaptic()
            },
            onInfo: { setInspectorVisible(!showInspector) },
            onPin: {
                item.isPinned.toggle()
                saveWithHaptic()
            },
            onDelete: { showDeleteConfirm = true }
        )
    }

    @ViewBuilder
    private var previewContent: some View {
        // Keep this branch at the same structural identity across Info toggles.
        // Resizing the preview must not recreate its Quick Look controller.
        ZStack {
            if isResolving {
                loadingState
            } else if let resolutionError {
                errorState(message: resolutionError)
            } else if let noteText {
                notePreview(noteText)
            } else if item.fileType == .image, let previewURL {
                // Local image viewer instead of Quick Look: QLPreviewController
                // hosts its content in a remote (XPC) view whose touches never
                // reach local gesture recognizers, so tap-to-toggle cannot work
                // there. This local view reuses the shared container tap gesture.
                // Full-bleed with zero clearances: the chrome floats above the
                // photo, so toggling never reflows the content (no jump), and the
                // letterbox follows the app theme instead of forced black.
                ImagePreviewView(url: previewURL, isZoomed: $imageZoomed)
            } else if item.fileType == .video || item.fileType == .audio, let previewURL {
                // Custom Photos-style player: a bare AVPlayerLayer with no
                // AVPlayerViewController transport bar, so there are no native
                // playback controls to collide with the Findly toolbar. The
                // slim scrubber lives in bottomChrome, stacked above the
                // toolbar; a single content tap toggles all chrome together.
                MediaPreviewView(url: previewURL, fileType: item.fileType, controller: mediaController)
            } else if item.fileType == .pdf, let previewURL {
                // Local PDF reader for the same reason: PDFView is a local
                // UIView, so container taps work; pan/pinch selection and zoom
                // keep working via the shared gesture delegate.
                PDFPreviewView(url: previewURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(ThemedPreviewBackground())
            } else if let previewURL {
                QuickLookController(url: previewURL, topClearance: chromeVisible ? headerControlHeight + 20 : 0, bottomClearance: chromeVisible ? FilePreviewToolbar.occupiedHeight : 0)
                    // Extend the native viewer through the home-indicator region.
                    // The sibling toolbar still observes the system safe area, and
                    // Quick Look retains its internal clearance for playback controls.
                    .ignoresSafeArea(.container, edges: [.top, .bottom])
            }
        }
    }

    @ViewBuilder
    private func notePreview(_ text: String) -> some View {
        Group {
            if text.isEmpty {
                ContentUnavailableView("Empty Note", systemImage: "note.text",
                                       description: Text("This note has no text."))
            } else {
                ScrollView {
                    Text(verbatim: text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.base)
                }
                // Constant margins: reserved space for the floating chrome even
                // when it is hidden, so toggling never reflows the text (no jump).
                .contentMargins(.top, headerControlHeight + 20, for: .scrollContent)
                .contentMargins(.bottom, FilePreviewToolbar.occupiedHeight, for: .scrollContent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(AppTheme.Colors.label)
        .background(AppTheme.Colors.background.ignoresSafeArea(.container, edges: [.top, .bottom]))
    }

/// Local zoomable image viewer. Used instead of Quick Look for images because
/// QLPreviewController renders in a remote (XPC) view whose touches never reach
/// local gesture recognizers, which made tap-to-toggle impossible there.
/// This view lives in the local hierarchy, so the shared container tap gesture
/// works; pinch zoom is handled locally via MagnificationGesture.
private struct ImagePreviewView: View {
    let url: URL
    /// Mirrors whether the photo is zoomed so the viewer can suspend
    /// drag-down-to-close while drags pan the zoomed photo instead.
    @Binding var isZoomed: Bool

    @State private var image: UIImage?
    @State private var loadFailed = false
    @State private var zoom: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: max(geometry.size.width, geometry.size.width * zoom),
                                height: max(geometry.size.height, geometry.size.height * zoom)
                            )
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                zoom = max(1, min(value.magnitude, 4))
                                isZoomed = zoom > 1.02
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    zoom = max(1, min(zoom, 4))
                                }
                                isZoomed = zoom > 1.02
                            }
                    )
                } else if loadFailed {
                    VStack(spacing: AppTheme.Spacing.small) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        Text("Unable to Open File")
                            .font(AppTheme.Typography.title3)
                            .foregroundStyle(AppTheme.Colors.label)
                        Text("This image could not be decoded.")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }
                    .padding(AppTheme.Spacing.xLarge)
                } else {
                    ProgressView()
                        .tint(AppTheme.Colors.label)
                        .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background.ignoresSafeArea(.container, edges: [.top, .bottom]))
        .task(id: url) {
            let decoded = await Self.downsampledImage(at: url)
            image = decoded
            loadFailed = decoded == nil
        }
        .onChange(of: url) { _, _ in
            zoom = 1
            isZoomed = false
        }
    }

    private static func downsampledImage(at url: URL, maxPixels: CGFloat = 2048) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels
            ] as CFDictionary
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

/// Photos-style video/audio surface: a bare AVPlayerLayer with no native
/// transport bar. Playback state lives in the shared MediaPlayerController
/// so the scrubber in bottomChrome stays in sync. The layer is a local
/// UIView, so the shared container tap gesture receives touches; the play,
/// mute, and slider controls are UIControls, which the tap coordinator
/// already excludes from content taps.
private struct MediaPreviewView: View {
    let url: URL
    let fileType: FileType
    var controller: MediaPlayerController

    var body: some View {
        ZStack {
            if fileType == .audio {
                audioArtwork
            } else {
                PlayerLayerView(player: controller.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Center affordance while paused or ended (like Photos).
            // A UIControl, so tapping it never toggles the chrome.
            // Solid dark circle keeps the glyph readable in both themes.
            if !controller.isPlaying {
                Button {
                    controller.togglePlay()
                } label: {
                    Image(systemName: controller.isEnded ? "arrow.counterclockwise" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(controller.isEnded ? "Replay" : "Play")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background.ignoresSafeArea(.container, edges: [.top, .bottom]))
        .task(id: url) {
            controller.configure(url: url)
        }
        .onDisappear {
            controller.teardown()
        }
    }

    private var audioArtwork: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.Colors.label.opacity(0.08))
                Image(systemName: fileType.sfSymbol)
                    .font(.system(size: 52))
                    .foregroundStyle(AppTheme.Colors.label)
            }
            .frame(width: 132, height: 132)
            Text(MediaTimeFormatter.string(from: controller.duration))
                .font(AppTheme.Typography.caption1)
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio preview")
    }
}

/// Hosts the controller's AVPlayer in a plain layer: aspect-fit with
/// letterbox bars following the app theme (like the image viewer).
private struct PlayerLayerView: UIViewRepresentable {
    var player: AVPlayer?

    func makeUIView(context: Context) -> PlayerRootView {
        let view = PlayerRootView()
        view.backgroundColor = .systemBackground
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.backgroundColor = UIColor.systemBackground.cgColor
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerRootView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

private final class PlayerRootView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Local PDF reader. PDFView is a local UIView, so the shared container tap
/// gesture receives touches; scroll/zoom/selection keep working through the
/// shared gesture delegate (pan/pinch/long-press yield first).
private struct PDFPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

private struct ThemedPreviewBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppTheme.Colors.background.ignoresSafeArea(.container, edges: [.top, .bottom]))
    }
}

    private var loadingState: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            ProgressView()
                .tint(AppTheme.Colors.label)
                .controlSize(.large)
            Text(item.googleDriveFileID == nil ? "Opening file…" : "Downloading from Google Drive…")
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
            VStack(spacing: AppTheme.Spacing.small) {
                Text("Unable to Open File")
                    .font(AppTheme.Typography.title3)
                    .foregroundStyle(AppTheme.Colors.label)
                Text(message)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: AppTheme.Spacing.medium) {
                Button("File Info") { openInspector() }
                    .buttonStyle(.bordered)
                Button("Retry") { Task { await resolveFile() } }
                    .buttonStyle(.borderedProminent)
            }
            .tint(AppTheme.Colors.accent)
        }
        .padding(AppTheme.Spacing.xLarge)
    }

    @MainActor
    private func resolveFile() async {
        guard !isResolving else { return }
        isResolving = true
        resolutionError = nil
        previewURL = nil
        noteText = nil
        defer { isResolving = false }

        let hasLocalFile: Bool
        if let relativePath = item.localFilePath {
            hasLocalFile = await appContainer.localStorage.exists(relativePath: relativePath)
        } else {
            hasLocalFile = false
        }

        switch FileResolutionStrategy.choose(
            hasLocalFile: hasLocalFile,
            hasRemoteFile: item.googleDriveFileID != nil
        ) {
        case .useLocalFile:
            guard let relativePath = item.localFilePath else { return }
            previewURL = await appContainer.localStorage.fileURL(relativePath: relativePath)
            await preparePreview()

        case .recoverFromDrive:
            do {
                try await appContainer.sync.recoverFromDrive(item: item)
                guard let relativePath = item.localFilePath,
                      await appContainer.localStorage.exists(relativePath: relativePath) else {
                    throw SyncError.noLocalFile
                }
                previewURL = await appContainer.localStorage.fileURL(relativePath: relativePath)
                await preparePreview()
            } catch {
                resolutionError = error.localizedDescription
            }

        case .unavailable:
            resolutionError = "The local file is missing and no Google Drive copy is available."
        }
    }

    @MainActor
    private func preparePreview() async {
        guard let previewURL else { return }
        do {
            if NotePreviewLoader.supports(fileType: item.fileType, originalFileName: item.originalFileName) {
                noteText = try await NotePreviewLoader.load(url: previewURL)
            }
            try Task.checkCancellation()
            recordSuccessfulOpen()
        } catch is CancellationError {
            // Closing the viewer must not publish a stale result or count an open.
        } catch {
            resolutionError = "Unable to read this note. " + error.localizedDescription
        }
    }

    private func recordSuccessfulOpen() {
        guard openSession.recordOpen(for: item) else { return }
        try? modelContext.save()
    }

    private func openInspector() {
        setInspectorVisible(true)
    }

    private func setInspectorVisible(_ visible: Bool) {
        guard !isDeleting else { return }
        withAnimation(reduceMotion ? nil : AppTheme.Animation.inspector) {
            if visible {
                controlsVisible = true
                inspectorDetent = .fraction(0.40)
            }
            showInspector = visible
        }
    }

    private func saveWithHaptic() {
        try? modelContext.save()
        HapticFeedback.light()
    }

    private func deleteItem() {
        guard !isDeleting else { return }
        isDeleting = true
        HapticFeedback.medium()
        Task {
            do {
                if let driveID = item.googleDriveFileID {
                    try await appContainer.drive.deleteFile(driveFileID: driveID)
                    item.googleDriveFileID = nil
                }
                if let path = item.localFilePath {
                    try await appContainer.localStorage.delete(relativePath: path)
                }
                modelContext.delete(item)
                try modelContext.save()
                viewerCoordinator.close()
            } catch {
                deleteError = error
                isDeleting = false
                HapticFeedback.error()
            }
        }
    }

}

/// Pure drag math for Photos-style drag-down-to-close. Kept free of SwiftUI
/// so the thresholds stay unit-testable. A drag only counts when it heads
/// mostly straight down, so horizontal scrub-seeks and diagonal pans can
/// never dismiss the viewer.
enum DismissDragEvaluator {
    static let minimumDistance: CGFloat = 20
    static let dismissThreshold: CGFloat = 140

    /// Follow-finger offset for a drag translation. Zero unless the drag
    /// heads downward and downward dominates horizontal movement.
    static func offset(for translation: CGSize) -> CGFloat {
        guard translation.height > 0, translation.height > abs(translation.width) else { return 0 }
        return translation.height
    }

    /// Whether a finished drag dismisses the viewer: past the distance
    /// threshold and clearly vertical.
    static func shouldDismiss(translation: CGSize) -> Bool {
        translation.height > dismissThreshold &&
        translation.height > abs(translation.width) * 1.5
    }

    /// Chrome fade while pulling down. Never fully zero so the header and
    /// toolbar ghost faintly until dismissal, like Photos.
    static func fade(for offset: CGFloat) -> Double {
        guard offset > 0 else { return 1 }
        return max(0.15, 1 - Double(offset) / 320)
    }
}

/// Pure playback math and labels for the Photos-style transport bar.
/// Kept free of AVFoundation so it stays unit-testable.
enum MediaTimeFormatter {
    /// Photos-style elapsed/remaining label: `m:ss`, or `h:mm:ss` past an hour.
    static func string(from seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "0:00" }
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Playback position as a 0...1 slider fraction. Returns 0 when the
    /// duration is unknown so the slider rests at the start, disabled.
    static func fraction(current: Double, duration: Double) -> Double {
        guard duration > 0, current.isFinite, duration.isFinite else { return 0 }
        return min(max(current / duration, 0), 1)
    }

    /// Seek target for a 0...1 slider fraction. Clamps out-of-range drags.
    static func time(forFraction fraction: Double, duration: Double) -> Double {
        guard duration > 0, duration.isFinite else { return 0 }
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1) * duration
    }
}

/// Owns the AVPlayer behind video/audio preview, Photos-style: autoplay with
/// sound on open, pause (hold last frame) at the end, explicit mute toggle.
/// A single shared instance drives both the layer and the scrubber, so the
/// two can never desync. Call `teardown()` when the preview leaves screen.
@Observable
@MainActor
final class MediaPlayerController {
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying = false
    var isMuted = false
    var isEnded = false
    var isScrubbing = false

    private(set) var player: AVPlayer?

    private var configuredURL: URL?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var wasPlayingBeforeScrub = false

    var canScrub: Bool { duration > 0 }

    /// Creates the player for `url` and autoplays with sound. No-op when the
    /// same URL is already configured, so repeated view updates are cheap.
    func configure(url: URL) {
        if configuredURL == url, player != nil { return }
        teardown()
        configuredURL = url
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        player.isMuted = isMuted
        self.player = player

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.handleTimeUpdate(time) }
        }
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in self?.handleStatus(observed.status, item: observed) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleEnded() }
        }
        if backgroundObserver == nil {
            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.pause() }
            }
        }
        player.play()
        isPlaying = true
    }

    /// Stops playback and releases every observer. Safe to call repeatedly.
    func teardown() {
        pause()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
            self.backgroundObserver = nil
        }
        player?.replaceCurrentItem(with: nil)
        player = nil
        configuredURL = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        isMuted = false
        isEnded = false
        isScrubbing = false
        wasPlayingBeforeScrub = false
    }

    /// Toggles playback. When the video ended, restarts from zero (replay).
    func togglePlay() {
        guard let player else { return }
        if isEnded {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = 0
            isEnded = false
            player.play()
            isPlaying = true
            return
        }
        if isPlaying {
            pause()
        } else {
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    /// Pauses for the duration of a slider drag; resumed in `endScrub()`.
    func beginScrub() {
        guard canScrub, !isScrubbing else { return }
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        player?.pause()
    }

    /// Seeks to a 0...1 slider fraction with frame precision for local files.
    func scrub(to fraction: Double) {
        guard canScrub else { return }
        let target = MediaTimeFormatter.time(forFraction: fraction, duration: duration)
        currentTime = target
        player?.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    /// Ends a slider drag, resuming playback only if it was playing before.
    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        isEnded = false
        if wasPlayingBeforeScrub {
            player?.play()
            isPlaying = true
        }
        wasPlayingBeforeScrub = false
    }

    private func handleTimeUpdate(_ time: CMTime) {
        // While scrubbing the thumb owns currentTime; observer updates would
        // fight the drag and make it jitter.
        guard !isScrubbing else { return }
        if time.isNumeric, time.seconds.isFinite {
            currentTime = time.seconds
        }
        if let itemDuration = player?.currentItem?.duration,
           itemDuration.isNumeric,
           itemDuration.seconds.isFinite,
           itemDuration.seconds > 0 {
            duration = itemDuration.seconds
        }
    }

    private func handleStatus(_ status: AVPlayerItem.Status, item: AVPlayerItem) {
        switch status {
        case .readyToPlay:
            let candidate = item.duration
            if candidate.isNumeric, candidate.seconds.isFinite, candidate.seconds > 0 {
                duration = candidate.seconds
            }
        case .failed:
            isPlaying = false
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handleEnded() {
        // Pause-at-end: hold the last frame with a replay affordance.
        isEnded = true
        isPlaying = false
        if duration > 0 {
            currentTime = duration
        }
    }
}

/// Slim Photos-style transport bar: play/pause, elapsed, slider, total, mute.
/// Rendered in bottomChrome directly above the Findly toolbar, hiding and
/// showing together with it. All controls are UIControls, so the shared
/// content-tap coordinator already excludes them from chrome toggles.
struct MediaScrubberView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var controller: MediaPlayerController

    var body: some View {
        HStack(spacing: 6) {
            Button {
                controller.togglePlay()
            } label: {
                Image(systemName: controller.isEnded ? "arrow.counterclockwise" : (controller.isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .accessibilityLabel(controller.isEnded ? "Replay" : (controller.isPlaying ? "Pause" : "Play"))

            Text(MediaTimeFormatter.string(from: controller.currentTime))
                .font(AppTheme.Typography.caption1)
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                .frame(minWidth: 36, alignment: .trailing)
                .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { MediaTimeFormatter.fraction(current: controller.currentTime, duration: controller.duration) },
                    set: { controller.scrub(to: $0) }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        controller.beginScrub()
                    } else {
                        controller.endScrub()
                    }
                }
            )
            .disabled(!controller.canScrub)
            .accessibilityLabel("Seek")
            .accessibilityValue("\(MediaTimeFormatter.string(from: controller.currentTime)) of \(MediaTimeFormatter.string(from: controller.duration))")

            Text(MediaTimeFormatter.string(from: controller.duration))
                .font(AppTheme.Typography.caption1)
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                .frame(minWidth: 36, alignment: .leading)
                .accessibilityHidden(true)

            Button {
                controller.toggleMute()
            } label: {
                Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")
            .accessibilityValue(controller.isMuted ? "Muted" : "Sound on")
        }
        .foregroundStyle(AppTheme.Colors.label)
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(surface, in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private var surface: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(.thinMaterial)
    }
}

/// Present secondary sheets/alerts from the visible surface, including when
/// the native metadata sheet is already open. Underlying actions stay hidden.
private struct FileActionPresentations: ViewModifier {
    let isActive: Bool
    @Binding var shareURL: URL?
    @Binding var showDeleteConfirm: Bool
    @Binding var deleteError: Error?
    var onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { isActive && shareURL != nil },
                set: { if isActive && !$0 { shareURL = nil } }
            )) {
                if let shareURL { ShareSheet(items: [shareURL]) }
            }
            .alert("Delete File?", isPresented: Binding(
                get: { isActive && showDeleteConfirm },
                set: { if isActive { showDeleteConfirm = $0 } }
            )) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the file from your vault and Google Drive.")
            }
            .alert("Delete Failed", isPresented: Binding(
                get: { isActive && deleteError != nil },
                set: { if isActive && !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError?.localizedDescription ?? "")
            }
    }
}

/// Observe a single content tap without cancelling native touches. Waiting for
/// zoom, pan, and long-press recognizers prevents those interactions from hiding
/// the chrome. Buttons and active text selections are never content taps.
struct PreviewContentTapGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    var onTap: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> PreviewTapCoordinator {
        PreviewTapCoordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.numberOfTapsRequired = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UITapGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended && isEnabled {
            onTap()
        }
    }
}

final class PreviewTapCoordinator: NSObject, UIGestureRecognizerDelegate {
    static func acceptsTarget(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UIControl || candidate.accessibilityTraits.contains(.link) { return false }
            if let text = candidate as? UITextView,
               text.isEditable || text.selectedRange.length > 0 { return false }
            current = candidate.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard Self.acceptsTarget(touch.view) else { return false }
        var current = touch.view
        while let candidate = current {
            if let text = candidate as? UITextView,
               let position = text.closestPosition(to: touch.location(in: text)) {
                let offset = text.offset(from: text.beginningOfDocument, to: position)
                if offset >= 0 && offset < text.attributedText.length &&
                    text.attributedText.attribute(.link, at: offset, effectiveRange: nil) != nil {
                    return false
                }
            }
            current = candidate.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        if let tap = other as? UITapGestureRecognizer { return tap.numberOfTapsRequired > 1 }
        return other is UILongPressGestureRecognizer || other is UIPanGestureRecognizer ||
            other is UIPinchGestureRecognizer
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Quick Look forwards touches through a remote gesture recognizer that
        // is not a UITapGestureRecognizer. Let that forwarding continue while
        // excluding the explicit zoom/scroll/selection gestures above.
        if let tap = other as? UITapGestureRecognizer { return tap.numberOfTapsRequired == 1 }
        return !(other is UIPanGestureRecognizer || other is UIPinchGestureRecognizer ||
                 other is UILongPressGestureRecognizer)
    }
}

/// Floating header with no full-width surface; only the controls carry material.
struct FilePreviewHeader: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: String
    var controlHeight: CGFloat = 44
    var isDeleting = false
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(surface, in: Circle())
                    .contentShape(Circle())
            }
            .disabled(isDeleting)
            .accessibilityLabel("Close file")
            Spacer(minLength: 0)
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 14)
                .frame(height: controlHeight)
                .background(surface, in: Capsule())
                .accessibilityLabel(title)
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .foregroundStyle(AppTheme.Colors.label)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var surface: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(.thinMaterial)
    }
}

/// Shared floating actions, presented by whichever surface is currently visible.
struct FilePreviewToolbar: View {
    static let occupiedHeight: CGFloat = 68

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isFavorite: Bool
    let isPinned: Bool
    let isInspectorVisible: Bool
    let canShare: Bool
    let isDeleting: Bool
    var onShare: () -> Void
    var onFavorite: () -> Void
    var onInfo: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            action("Share file", symbol: "square.and.arrow.up", action: onShare)
                .disabled(!canShare)
                .opacity(canShare ? 1 : 0.4)
                .background(surface, in: Circle())
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                action("Favourite", symbol: isFavorite ? "heart.fill" : "heart",
                       value: isFavorite ? "On" : "Off", action: onFavorite)
                    .foregroundStyle(isFavorite ? AppTheme.Colors.favoriteTint : AppTheme.Colors.label)
                action("File information", symbol: isInspectorVisible ? "info.circle.fill" : "info.circle",
                       value: isInspectorVisible ? "Expanded" : "Collapsed", action: onInfo)
                action("Pin", symbol: isPinned ? "pin.fill" : "pin",
                       value: isPinned ? "On" : "Off", action: onPin)
                    .foregroundStyle(isPinned ? AppTheme.Colors.pinnedTint : AppTheme.Colors.label)
            }
            .padding(.horizontal, 4)
            .background(surface, in: Capsule())
            Spacer(minLength: 0)
            Button(role: .destructive, action: onDelete) {
                Group {
                    if isDeleting {
                        ProgressView().tint(AppTheme.Colors.label)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
            }
            .accessibilityLabel("Delete file")
            .accessibilityValue(isDeleting ? "Deleting" : "")
            .background(surface, in: Circle())
        }
        .font(.title3)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundStyle(AppTheme.Colors.label)
        .buttonStyle(.plain)
        .disabled(isDeleting)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private var surface: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(.thinMaterial)
    }

    private func action(_ label: String, symbol: String, value: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct QuickLookController: UIViewControllerRepresentable {
    let url: URL
    let topClearance: CGFloat
    let bottomClearance: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        // Pure black so aspect-fit letterbox bars blend with the viewer chrome.
        controller.view.backgroundColor = .black
        controller.additionalSafeAreaInsets.top = topClearance
        controller.additionalSafeAreaInsets.bottom = bottomClearance
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        // Inset native controls without shortening the full-screen background.
        controller.additionalSafeAreaInsets.top = topClearance
        controller.additionalSafeAreaInsets.bottom = bottomClearance
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct MetadataInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let item: Item
    let resolvedURL: URL?
    @Binding var selectedDetent: PresentationDetent
    let isDeleting: Bool
    var onRetry: () -> Void

    @State private var titleText: String
    @State private var descriptionText: String
    @State private var descriptionBeforeEditing: String
    @State private var isAddingDescription = false
    @State private var isDetailsExpanded = false
    @State private var showTagPicker = false
    @FocusState private var focusedField: Field?

    private enum Field { case title, description }

    init(
        item: Item,
        resolvedURL: URL?,
        selectedDetent: Binding<PresentationDetent>,
        isDeleting: Bool,
        onRetry: @escaping () -> Void
    ) {
        self.item = item
        self.resolvedURL = resolvedURL
        _selectedDetent = selectedDetent
        self.isDeleting = isDeleting
        self.onRetry = onRetry
        _titleText = State(initialValue: item.title)
        _descriptionText = State(initialValue: item.itemDescription)
        _descriptionBeforeEditing = State(initialValue: item.itemDescription)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.large) {
                    header
                    descriptionSection
                    tagsSection
                    detailsSection
                    syncSection
                }
                .padding(.horizontal, AppTheme.Spacing.base)
                .padding(.bottom, AppTheme.Spacing.xLarge)
            }
            .contentMargins(.bottom, FilePreviewToolbar.occupiedHeight, for: .scrollContent)
            // First upward swipe inside the panel grows it from 40% to 60%,
            // so scrolling to see lower content also gives more room. One-way
            // only: never auto-collapses, and the grabber stays for manual
            // 40% <-> 60% dragging. Simultaneous so the ScrollView still scrolls.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard selectedDetent != .fraction(0.60) else { return }
                        guard value.translation.height < -16,
                              abs(value.translation.height) > abs(value.translation.width) else { return }
                        withAnimation(reduceMotion ? nil : AppTheme.Animation.inspector) {
                            selectedDetent = .fraction(0.60)
                        }
                    }
            )
            .background(AppTheme.Colors.groupedBG.ignoresSafeArea(.container, edges: .bottom))
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .description {
                        Button("Cancel") { cancelDescriptionEditing() }
                    }
                    Spacer()
                    Button("Done") { finishEditing() }
                }
            }
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .title && newValue != .title { commitTitle() }
            if oldValue == .description && newValue != .description {
                finishDescriptionEditing(clearFocus: false)
            }
            if newValue == .title { selectedDetent = .fraction(0.60) }
            if oldValue == .title && newValue == nil && !isDetailsExpanded { selectedDetent = .fraction(0.40) }
            if newValue == .description {
                descriptionBeforeEditing = item.itemDescription
                withAnimation(reduceMotion ? nil : AppTheme.Animation.inspector) {
                    isAddingDescription = true
                    isDetailsExpanded = false
                    selectedDetent = .fraction(0.60)
                }
            }
        }
        .onDisappear {
            guard !isDeleting else { return }
            commitTitle()
            commitDescription()
        }
        .sheet(isPresented: $showTagPicker) {
            TagPickerSheet(item: item, onToggle: toggleTag)
        }
        .disabled(isDeleting)
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(item.fileType.tintColor.opacity(0.12))
                Image(systemName: item.fileType.sfSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.fileType.tintColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                TextField("File name", text: $titleText)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.label)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { commitTitle() }
                    .accessibilityLabel("File name")
                HStack(spacing: 6) {
                    Text("\(item.fileType.displayName) · \(item.fileSize.fileSizeString)")
                        .lineLimit(1)
                    Spacer(minLength: AppTheme.Spacing.small)
                    HStack(spacing: 4) {
                        SyncStatusBadge(status: item.syncStatus)
                        Text(item.syncStatus.displayLabel)
                            .foregroundStyle(item.syncStatus.tintColor)
                            .lineLimit(1)
                    }
                }
                .font(AppTheme.Typography.caption1)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppTheme.Spacing.small)
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if hasDescription || isAddingDescription || focusedField == .description {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label("Description", systemImage: "text.alignleft")
                    .font(AppTheme.Typography.caption1.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)

                TextField("Add a description", text: $descriptionText, axis: .vertical)
                    .lineLimit(1...4)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.label)
                    .focused($focusedField, equals: .description)
                    .accessibilityLabel("File description")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.Colors.secondaryBG)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        } else {
            Button(action: beginAddingDescription) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.Colors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    Text("Add a description")
                        .font(AppTheme.Typography.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.label)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(AppTheme.Colors.accent)
                }
                .padding(AppTheme.Spacing.medium)
                .background(AppTheme.Colors.secondaryBG)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a description")
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text("Tags")
                .font(AppTheme.Typography.caption1.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.secondaryLabel)

            FlowLayout(
                spacing: AppTheme.Spacing.small,
                verticalSpacing: AppTheme.Spacing.xxSmall
            ) {
                ForEach(item.tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { tag in
                    removableTagChip(tag)
                }
                addTagChip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailsSection: some View {
        VStack(spacing: 0) {
            Button(action: toggleDetails) {
                HStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.Colors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("More Details")
                            .font(AppTheme.Typography.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.label)
                        Text("Added \(item.createdAt.relativeString) · \(viewCountText)")
                            .font(AppTheme.Typography.caption2)
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        .rotationEffect(.degrees(isDetailsExpanded ? 180 : 0))
                }
                .padding(AppTheme.Spacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDetailsExpanded ? "Collapse file details" : "Expand file details")
            .accessibilityValue(isDetailsExpanded ? "Expanded" : "Collapsed")

            if isDetailsExpanded {
                VStack(spacing: AppTheme.Spacing.medium) {
                    activityRow(
                        symbol: "doc",
                        title: "Original File",
                        primary: item.originalFileName.isEmpty ? "Not available" : item.originalFileName
                    )
                    activityRow(
                        symbol: "calendar.badge.plus",
                        title: "Added",
                        primary: item.createdAt.relativeString,
                        secondary: item.createdAt.fullDateTimeString
                    )
                    activityRow(
                        symbol: "pencil",
                        title: "Modified",
                        primary: item.modifiedAt.relativeString,
                        secondary: item.modifiedAt.fullDateTimeString
                    )
                    if let opened = item.lastOpenedAt {
                        activityRow(
                            symbol: "clock.arrow.circlepath",
                            title: "Last Opened",
                            primary: opened.relativeString,
                            secondary: opened.fullDateTimeString
                        )
                    }
                    activityRow(symbol: "eye", title: "Views", primary: viewCountText)
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.bottom, AppTheme.Spacing.medium)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppTheme.Colors.secondaryBG)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
    }

    @ViewBuilder
    private var syncSection: some View {
        if resolvedURL == nil, item.googleDriveFileID != nil {
            Button(action: onRetry) {
                Label("Download from Google Drive", systemImage: "icloud.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.medium)
            }
            .buttonStyle(.borderedProminent)
        } else if item.syncStatus == .localOnly {
            if appContainer.auth.isAuthenticated {
                Button { performSyncAction() } label: {
                    Label("Back Up to Google Drive", systemImage: "icloud.and.arrow.up.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.medium)
                }
                .buttonStyle(.bordered)
            } else {
                Label("Connect Google Drive in Settings to back up this file.", systemImage: "iphone")
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    .frame(maxWidth: .infinity)
            }
        } else if item.syncStatus == .failed, appContainer.auth.isAuthenticated {
            Button { performSyncAction() } label: {
                Label("Retry Google Drive Sync", systemImage: "arrow.clockwise.icloud.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.medium)
            }
            .buttonStyle(.bordered)
        }
    }

    private var hasDescription: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var viewCountText: String {
        switch item.viewCount {
        case 0: "Never opened"
        case 1: "Opened once"
        default: "Opened \(item.viewCount) times"
        }
    }

    private var addTagChip: some View {
        Button { showTagPicker = true } label: {
            Label("Add Tag", systemImage: "plus")
                .font(AppTheme.Typography.caption1.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.accent)
                .padding(.horizontal, AppTheme.Spacing.medium)
                .frame(minHeight: 36)
                .background(AppTheme.Colors.accent.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Add or edit tags")
    }

    private func removableTagChip(_ tag: Tag) -> some View {
        Button { removeTag(tag) } label: {
            HStack(spacing: AppTheme.Spacing.xSmall) {
                TagSymbolView(sfSymbol: tag.sfSymbol, color: Color(hex: tag.colorHex), size: 11)
                Text(tag.name)
                    .font(AppTheme.Typography.caption1.weight(.medium))
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color(hex: tag.colorHex).opacity(0.75))
            }
            .foregroundStyle(Color(hex: tag.colorHex))
            .padding(.horizontal, AppTheme.Spacing.medium)
            .frame(minHeight: 36)
            .background(Color(hex: tag.colorHex).opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Remove \(tag.name) tag")
    }

    private func activityRow(
        symbol: String,
        title: String,
        primary: String,
        secondary: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 30, height: 30)
                .background(AppTheme.Colors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.caption1)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                Text(primary)
                    .font(AppTheme.Typography.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.label)
                if let secondary {
                    Text(secondary)
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func toggleDetails() {
        let expanded = !isDetailsExpanded
        if expanded {
            finishDescriptionEditing(clearFocus: true, collapsePanel: false)
        }
        withAnimation(reduceMotion ? nil : AppTheme.Animation.inspector) {
            isDetailsExpanded = expanded
            selectedDetent = .fraction(expanded ? 0.60 : 0.40)
        }
    }

    private func beginAddingDescription() {
        withAnimation(reduceMotion ? nil : AppTheme.Animation.inspector) {
            isAddingDescription = true
            isDetailsExpanded = false
            selectedDetent = .fraction(0.60)
        }
        focusedField = .description
    }

    private func finishEditing() {
        switch focusedField {
        case .title:
            commitTitle()
            focusedField = nil
        case .description:
            finishDescriptionEditing(clearFocus: true)
        case nil:
            break
        }
    }

    private func finishDescriptionEditing(clearFocus: Bool, collapsePanel: Bool = true) {
        commitDescription()
        if clearFocus { focusedField = nil }
        withAnimation(reduceMotion ? nil : AppTheme.Animation.inspector) {
            isAddingDescription = false
            if collapsePanel && !isDetailsExpanded {
                selectedDetent = .fraction(0.40)
            }
        }
    }

    private func cancelDescriptionEditing() {
        descriptionText = descriptionBeforeEditing
        focusedField = nil
    }

    private func commitTitle() {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            titleText = item.title
            return
        }
        guard trimmed != item.title else { return }
        item.title = trimmed
        item.markModified()
        try? modelContext.save()
        HapticFeedback.light()
    }

    private func commitDescription() {
        let trimmed = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != item.itemDescription else { return }
        descriptionText = trimmed
        item.itemDescription = trimmed
        item.markModified()
        try? modelContext.save()
        HapticFeedback.light()
    }

    private func toggleTag(_ tag: Tag) {
        if item.tags.contains(where: { $0.id == tag.id }) {
            removeTag(tag)
        } else {
            item.tags.append(tag)
            item.markModified()
            try? modelContext.save()
            HapticFeedback.light()
        }
    }

    private func removeTag(_ tag: Tag) {
        item.tags.removeAll { $0.id == tag.id }
        item.markModified()
        try? modelContext.save()
        HapticFeedback.light()
    }

    private func performSyncAction() {
        if resolvedURL == nil {
            onRetry()
            return
        }
        guard appContainer.auth.isAuthenticated else { return }
        Task {
            if item.syncStatus == .localOnly {
                appContainer.sync.promoteLocalOnlyItems()
            } else if item.syncStatus == .failed {
                item.syncStatus = .pending
                try? modelContext.save()
            }
            await appContainer.sync.syncPendingItems()
        }
    }

}

// MARK: - Tag picker sheet

struct TagPickerSheet: View {
    let item: Item
    var onToggle: (Tag) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var allTags: [Tag] = []
    @State private var searchText = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredTags: [Tag] {
        guard !trimmedSearchText.isEmpty else { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearchText) }
    }

    private var canCreate: Bool {
        !trimmedSearchText.isEmpty &&
        !allTags.contains { $0.name.caseInsensitiveCompare(trimmedSearchText) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if canCreate {
                    Button(action: createTag) {
                        Label("Create \"\(trimmedSearchText)\"", systemImage: "plus.circle.fill")
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                }
                if filteredTags.isEmpty && !canCreate {
                    Text(allTags.isEmpty ? "No tags created yet." : "No tags match your search.")
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredTags) { tag in
                        Button {
                            onToggle(tag)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.medium) {
                                TagSymbolView(sfSymbol: tag.sfSymbol, color: Color(hex: tag.colorHex), size: 14)
                                    .frame(width: 22, height: 22)
                                    .background(Color(hex: tag.colorHex).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(tag.name)
                                    .foregroundStyle(AppTheme.Colors.label)
                                Spacer()
                                if isSelected(tag) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.Colors.accent)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                                }
                            }
                        }
                        .accessibilityLabel(tag.name)
                        .accessibilityValue(isSelected(tag) ? "Selected" : "Not selected")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search or create tag...")
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                allTags = ((try? modelContext.fetch(FetchDescriptor<Tag>(
                    sortBy: [SortDescriptor(\.name)]
                ))) ?? [])
            }
        }
    }

    private func isSelected(_ tag: Tag) -> Bool {
        item.tags.contains(where: { $0.id == tag.id })
    }

    private func createTag() {
        guard canCreate else { return }
        let colors = ["#3498DB", "#E74C3C", "#2ECC71", "#F39C12", "#9B59B6", "#1ABC9C"]
        let hex = colors.randomElement() ?? "#3498DB"
        let tag = Tag(name: trimmedSearchText, colorHex: hex, sfSymbol: "tag.fill")
        modelContext.insert(tag)
        allTags.append(tag)
        allTags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try? modelContext.save()
        onToggle(tag)
        searchText = ""
    }
}

// MARK: - Simple flow layout for tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var verticalSpacing: CGFloat? = nil

    private var resolvedVerticalSpacing: CGFloat {
        verticalSpacing ?? spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                height += rowHeight + resolvedVerticalSpacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + resolvedVerticalSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
