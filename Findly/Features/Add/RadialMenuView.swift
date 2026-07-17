import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Full-screen radial menu overlay shown on long-pressing the + FAB.
/// Displays 5 file-type options as liquid-glass circles fanning out in a quarter-arc above the FAB.
/// Supports drag-to-select: hold the FAB, drag to an icon, release to select it.
struct RadialMenuView: View {

    @Binding var isVisible: Bool
    /// Current drag position in global screen coordinates (nil when not dragging).
    var dragPoint: CGPoint? = nil
    /// Increments each time a drag gesture ends; triggers option selection and menu close.
    var dragEndTrigger: Int = 0

    @Environment(AppContainer.self) private var appContainer
    @Environment(\.modelContext) private var modelContext

    // MARK: - Visual state

    @State private var isDismissing = false
    @State private var animationProgress: [Bool] = Array(repeating: false, count: 5)
    /// Index of the icon currently under the user's finger during a drag.
    @State private var hoveredIndex: Int? = nil
    /// Actual global center of the FAB placeholder — captured via GeometryReader on appear.
    /// Used for accurate icon hit-testing regardless of safe area insets.
    @State private var anchorPosition: CGPoint = .zero

    // MARK: - Picker state

    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var photoPickerActive = false

    @State private var showFileImporter = false

    @State private var showNoteComposer = false
    @State private var showLinkComposer = false
    @State private var showCameraPicker = false

    @State private var pendingUpload: PendingUpload? = nil

    // MARK: - Layout constants

    private let options: [AddOption] = [.photo, .camera, .document, .note, .link]
    private let angles: [Double] = [90, 135, 180, 225, 270]
    private let radius: CGFloat = 105
    private let fabTrailingPad: CGFloat = AppTheme.Spacing.large
    private let fabBottomOffset: CGFloat = 90 + 28

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            dimBackground
            iconFan
        }
        .onAppear { animateIn() }
        .onChange(of: dragPoint) { _, pt in
            // Update hovered icon as finger moves
            hoveredIndex = pt.flatMap { closestIconIndex(to: $0) }
        }
        .onChange(of: dragEndTrigger) { _, _ in
            // Touch lifted — select hovered option or just close
            if let idx = hoveredIndex {
                HapticFeedback.light()
                dismissMenuVisual()
                handleOption(options[idx])
            } else {
                dismissAndClose()
            }
            hoveredIndex = nil
        }
        // MARK: Pickers & sheets
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $selectedPhotoItem,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            photoPickerActive = false
            Task { await handlePhotoPickerItem(item) }
        }
        .onChange(of: showPhotosPicker) { _, showing in
            guard !showing, photoPickerActive else { return }
            photoPickerActive = false
            isVisible = false
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            showFileImporter = false
            switch result {
            case .success(let urls):
                guard let url = urls.first else { isVisible = false; return }
                Task { await handleDocumentURL(url) }
            case .failure:
                isVisible = false
            }
        }
        .sheet(isPresented: $showNoteComposer, onDismiss: {
            if pendingUpload == nil { isVisible = false }
        }) {
            NoteComposerView { title, content in
                let data = content.data(using: .utf8) ?? Data()
                pendingUpload = PendingUpload(
                    data: data,
                    fileName: "\(title).txt",
                    fileType: .note,
                    suggestedTitle: title
                )
                showNoteComposer = false
            }
            .environment(appContainer)
        }
        .sheet(isPresented: $showLinkComposer, onDismiss: {
            if pendingUpload == nil { isVisible = false }
        }) {
            LinkComposerView { title, urlString in
                let data = urlString.data(using: .utf8) ?? Data()
                pendingUpload = PendingUpload(
                    data: data,
                    fileName: "\(title).webloc",
                    fileType: .link,
                    suggestedTitle: title
                )
                showLinkComposer = false
            }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPickerView(
                onResult: { result in
                    showCameraPicker = false
                    Task { await handleCameraResult(result) }
                },
                onCancel: {
                    showCameraPicker = false
                    isVisible = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $pendingUpload, onDismiss: {
            // Covers the cancel case: user swipes away ItemFormView without completing the upload.
            isVisible = false
        }) { upload in
            ItemFormView(pendingUpload: upload) {
                isVisible = false
            }
            .environment(appContainer)
        }
    }

    // MARK: - Subviews

    private var dimBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
            .onTapGesture { dismissAndClose() }
            .opacity(isDismissing ? 0 : 1)
            .animation(.easeOut(duration: 0.15), value: isDismissing)
    }

    private var iconFan: some View {
        HStack(alignment: .bottom) {
            Spacer()
            ZStack {
                // Anchor placeholder: same size as the FAB.
                // A GeometryReader captures its actual global center so icon hit-testing
                // is accurate regardless of safe-area insets or device size.
                Color.clear
                    .frame(width: 56, height: 56)
                    .background(
                        GeometryReader { geo in
                            Color.clear.onAppear {
                                let frame = geo.frame(in: .global)
                                anchorPosition = CGPoint(x: frame.midX, y: frame.midY)
                            }
                        }
                    )

                ForEach(Array(zip(options.indices, options)), id: \.0) { index, option in
                    let rad = angles[index] * .pi / 180
                    glassButton(option: option, index: index)
                        .offset(
                            x: radius * CGFloat(cos(rad)),
                            y: radius * CGFloat(sin(rad))
                        )
                }
            }
            .padding(.trailing, fabTrailingPad)
        }
        .padding(.bottom, fabBottomOffset - 28)
    }

    @ViewBuilder
    private func glassButton(option: AddOption, index: Int) -> some View {
        let isHovered = hoveredIndex == index
        Button {
            dismissMenuVisual()
            handleOption(option)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .stroke(isHovered ? Color.white.opacity(0.7) : Color.white.opacity(0.35),
                                        lineWidth: isHovered ? 1.5 : 0.5)
                        )
                        .overlay(
                            Circle()
                                .fill(isHovered ? Color.white.opacity(0.15) : Color.clear)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)

                    Image(systemName: option.customSymbol ?? option.fileType.addSheetSymbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(option.fileType.tintColor)
                }

                Text(option.radialLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(animationProgress[index] ? (isHovered ? 1.15 : 1.0) : 0.3)
        .opacity(animationProgress[index] ? 1.0 : 0.0)
        // No built-in delay here — all staggering is driven via asyncAfter in animateIn/dismissMenuVisual
        // so open and close can use different orderings without fighting each other.
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: animationProgress[index])
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
    }

    // MARK: - Animation helpers

    private func animateIn() {
        // Stagger icons in forward order (0 → last).
        for i in options.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                animationProgress[i] = true
            }
        }
    }

    /// Plays the reverse close animation (icons collapse last → first, then background fades).
    /// Call `handleOption` immediately after if an option was selected — the picker appears
    /// while the icons are still animating out.
    private func dismissMenuVisual() {
        // Stagger icons out in reverse order (last → 0).
        for i in options.indices.reversed() {
            let delay = Double(options.count - 1 - i) * 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                animationProgress[i] = false
            }
        }
        // Fade the background after the last icon starts collapsing.
        let bgDelay = Double(options.count - 1) * 0.05 + 0.18
        DispatchQueue.main.asyncAfter(deadline: .now() + bgDelay) {
            withAnimation(.easeOut(duration: 0.15)) {
                isDismissing = true
            }
        }
    }

    private func dismissAndClose() {
        dismissMenuVisual()
        // Remove from hierarchy after the full close animation completes.
        let closeDelay = Double(options.count - 1) * 0.05 + 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay) {
            isVisible = false
        }
    }

    // MARK: - Drag hit-test helpers

    /// Returns the global center of the icon at `index`, derived from the captured FAB anchor position.
    private func iconCenter(at index: Int) -> CGPoint {
        let rad = angles[index] * .pi / 180
        return CGPoint(
            x: anchorPosition.x + radius * CGFloat(cos(rad)),
            y: anchorPosition.y + radius * CGFloat(sin(rad))
        )
    }

    /// Returns the index of the icon whose center is closest to `point` within 55 pt, or nil.
    private func closestIconIndex(to point: CGPoint) -> Int? {
        // Wait until anchor is captured (non-zero means it's been set)
        guard anchorPosition != .zero else { return nil }
        let threshold: CGFloat = 55
        var bestIndex: Int? = nil
        var bestDist: CGFloat = threshold
        for i in options.indices {
            let center = iconCenter(at: i)
            let dist = hypot(point.x - center.x, point.y - center.y)
            if dist < bestDist {
                bestDist = dist
                bestIndex = i
            }
        }
        return bestIndex
    }

    // MARK: - Option routing

    private func handleOption(_ option: AddOption) {
        switch option {
        case .photo:
            photoPickerActive = true
            showPhotosPicker = true
        case .camera:
            showCameraPicker = true
        case .document:
            showFileImporter = true
        case .note:
            showNoteComposer = true
        case .link:
            showLinkComposer = true
        default:
            break
        }
    }

    // MARK: - Upload handlers

    private func handlePhotoPickerItem(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            await MainActor.run { isVisible = false }
            return
        }
        let isVideo = item.supportedContentTypes.contains {
            $0.conforms(to: .movie) || $0.conforms(to: .video)
        }
        let fileType: FileType = isVideo ? .video : .image
        let ext = isVideo ? "mp4" : "jpg"
        let name = item.itemIdentifier ?? UUID().uuidString
        await MainActor.run {
            selectedPhotoItem = nil
            pendingUpload = PendingUpload(
                data: data,
                fileName: "\(name).\(ext)",
                fileType: fileType,
                suggestedTitle: isVideo ? "Video" : "Photo"
            )
        }
    }

    private func handleDocumentURL(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            await MainActor.run { isVisible = false }
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            await MainActor.run { isVisible = false }
            return
        }
        let ft = FileType.detect(fileExtension: url.pathExtension)
        await MainActor.run {
            pendingUpload = PendingUpload(
                data: data,
                fileName: url.lastPathComponent,
                fileType: ft,
                suggestedTitle: url.deletingPathExtension().lastPathComponent
            )
        }
    }

    private func handleCameraResult(_ result: CameraResult) async {
        let dateStamp = Date().fullDateString
        switch result {
        case .photo(let image):
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                await MainActor.run { isVisible = false }
                return
            }
            await MainActor.run {
                pendingUpload = PendingUpload(
                    data: data,
                    fileName: "camera_\(UUID().uuidString).jpg",
                    fileType: .image,
                    suggestedTitle: "Camera Photo — \(dateStamp)"
                )
            }
        case .video(let url):
            let videoSize = Int64(
                (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            )
            await MainActor.run {
                pendingUpload = PendingUpload(
                    data: Data(),
                    fileName: "camera_\(UUID().uuidString).mp4",
                    fileType: .video,
                    suggestedTitle: "Camera Video — \(dateStamp)",
                    fileSize: videoSize,
                    sourceURL: url
                )
            }
        }
    }
}

// MARK: - Short label for radial menu display

extension AddOption {
    var radialLabel: String {
        switch self {
        case .photo:    return "Photo"
        case .camera:   return "Camera"
        case .document: return "File"
        case .note:     return "Note"
        case .link:     return "Link"
        default:        return label
        }
    }
}
