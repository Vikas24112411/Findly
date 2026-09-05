import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Full-screen radial menu overlay shown on long-pressing the + FAB.
/// Displays five labeled options fanning upward and left from the FAB.
/// Supports drag-to-select: hold the FAB, drag to an icon, release to select it.
struct RadialMenuView: View {

    @Binding var isVisible: Bool
    /// Current drag position in global screen coordinates (nil when not dragging).
    var dragPoint: CGPoint? = nil
    /// Increments each time a drag gesture ends; triggers option selection and menu close.
    var dragEndTrigger: Int = 0
    /// Called immediately when the user commits to an option (before the picker opens),
    /// so the parent can reset the FAB icon without waiting for the full picker flow to finish.
    var onOptionCommitted: (() -> Void)? = nil

    @Environment(AppContainer.self) private var appContainer
    @Environment(\.modelContext) private var modelContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: - Visual state

    @State private var isDismissing = false
    @State private var isExpanded = false
    /// Three-level hover state for drag-to-select feedback.
    private enum HoverState: Equatable {
        case none
        case pending(Int)    // inside dead zone (0–52 pt) — soft preview, does NOT commit on release
        case confirmed(Int)  // past dead zone (≥52 pt) — full highlight, commits on release

        var confirmedIndex: Int? {
            if case .confirmed(let i) = self { return i }
            return nil
        }
    }

    @State private var hoverState: HoverState = .none
    /// Actual global center of the FAB placeholder — captured via GeometryReader on appear.
    /// Used for accurate icon hit-testing regardless of safe area insets.
    @State private var anchorPosition: CGPoint? = nil

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

    // Keep the original option order, with the lower endpoint lifted clear of the tab bar.
    private let options: [AddOption] = [.link, .note, .document, .camera, .photo]
    private let angles: [Double] = [165, 191.25, 217.5, 243.75, 270]
    private let radius: CGFloat = 164

    private var menuAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.86)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            dimBackground
            if dynamicTypeSize.isAccessibilitySize {
                accessibleOptions
            } else {
                iconFan
            }
        }
        .accessibilityHidden(!isVisible || isDismissing)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { dismissAndClose() }
        .onChange(of: isVisible) { _, visible in
            hoverState = .none
            if visible {
                isDismissing = false
                withAnimation(menuAnimation) { isExpanded = true }
            } else {
                isExpanded = false
            }
        }
        .onChange(of: dragPoint) { _, pt in
            guard isVisible, !isDismissing, !dynamicTypeSize.isAccessibilitySize else { return }
            let newState = pt.map { computeHoverState(for: $0) } ?? .none
            fireHapticIfNeeded(from: hoverState, to: newState)
            hoverState = newState
        }
        .onChange(of: dragEndTrigger) { _, _ in
            guard isVisible, !isDismissing else { return }
            guard !dynamicTypeSize.isAccessibilitySize else { return }
            // Recompute from the release point; hover updates may be coalesced in this frame.
            if let idx = dragPoint.flatMap({ computeHoverState(for: $0).confirmedIndex }) {
                // Past dead zone — commit the selection
                HapticFeedback.light()
                onOptionCommitted?()
                dismissMenuVisual()
                handleOption(options[idx])
            } else {
                // Dead zone or outside arc — cancel
                dismissAndClose()
            }
            hoverState = .none
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
        .fullScreenCover(isPresented: $showCameraPicker, onDismiss: {
            // Safety net: if the cover is dismissed without going through onCancel
            // (e.g. by a system gesture), ensure the menu is closed.
            if pendingUpload == nil { isVisible = false }
        }) {
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
        Button(action: dismissAndClose) {
            Rectangle()
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(uiColor: .systemBackground))
                      : AnyShapeStyle(.regularMaterial))
                .ignoresSafeArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close upload options")
        .opacity(isExpanded ? 1 : 0)
        .allowsHitTesting(!isDismissing)
    }

    private var iconFan: some View {
        HStack(alignment: .bottom) {
            Spacer()
            Color.clear
                .frame(width: 56, height: 56)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    anchorPosition = CGPoint(x: frame.midX, y: frame.midY)
                }
                .overlay {
                    ZStack {
                        Button(action: dismissAndClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(AppTheme.Colors.accent, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close upload options")
                        ForEach(options.indices, id: \.self) { index in
                            let rad = angles[index] * .pi / 180
                            optionButton(options[index], index: index)
                                .offset(
                                    x: radius * CGFloat(cos(rad)) * (isExpanded || reduceMotion ? 1 : 0),
                                    y: radius * CGFloat(sin(rad)) * (isExpanded || reduceMotion ? 1 : 0)
                                )
                        }
                    }
                }
                .padding(.trailing, AppTheme.Spacing.large)
        }
        .padding(.bottom, 90)
        .opacity(isExpanded ? 1 : 0)
        .allowsHitTesting(isExpanded && !isDismissing)
    }

    private var accessibleOptions: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Add to Vault").font(.headline)
                ForEach(options.indices, id: \.self) { index in
                    Button { commit(options[index]) } label: {
                        Label(options[index].radialLabel,
                              systemImage: options[index].customSymbol ?? options[index].fileType.addSheetSymbol)
                            .font(.body)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                Button("Cancel", action: dismissAndClose).padding()
            }
            .padding(24)
        }
        .opacity(isExpanded ? 1 : 0)
        .allowsHitTesting(isExpanded && !isDismissing)
    }

    private func optionButton(_ option: AddOption, index: Int) -> some View {
        let selected = hoverState == .confirmed(index)
        return Button { commit(option) } label: {
            VStack(spacing: 6) {
                Image(systemName: option.customSymbol ?? option.fileType.addSheetSymbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : option.fileType.tintColor)
                    .frame(width: 54, height: 54)
                    .background(selected ? AppTheme.Colors.accent : Color(uiColor: .secondarySystemBackground), in: Circle())
                    .overlay {
                        Circle().strokeBorder(selected ? AppTheme.Colors.accent : Color.primary.opacity(contrast == .increased ? 0.6 : 0.12), lineWidth: selected ? 3 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white, AppTheme.Colors.accent)
                        }
                    }
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
                Text(option.radialLabel)
                    .font(.caption.weight(selected ? .bold : .medium))
                    .foregroundStyle(.primary)
                    .fixedSize()
            }
            .frame(width: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.radialLabel)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .scaleEffect(selected && !reduceMotion ? 1.06 : 1)
        .animation(menuAnimation, value: hoverState)
    }

    private func commit(_ option: AddOption) {
        guard isVisible, !isDismissing else { return }
        HapticFeedback.light()
        onOptionCommitted?()
        dismissMenuVisual()
        handleOption(option)
    }

    private func dismissMenuVisual() {
        isDismissing = true
        withAnimation(menuAnimation) { isExpanded = false }
    }

    private func dismissAndClose() {
        guard !isDismissing else { return }
        isDismissing = true
        withAnimation(menuAnimation, completionCriteria: .logicallyComplete) {
            isExpanded = false
        } completion: {
            guard isDismissing else { return }
            isVisible = false
        }
    }

    // MARK: - Drag hit-test helpers

    /// Fires haptic feedback for notable hover-state transitions:
    /// - `.pending → .confirmed` (same sector): medium tap — "you can release now"
    /// - `.none → .confirmed`: medium tap — fast drag skipped the dead zone
    /// - `.confirmed(i) → .confirmed(j)`: rigid tick — sector boundary crossed while committed
    /// - `.pending(i) → .pending(j)`: light tick — sector boundary crossed while uncommitted
    /// - `.confirmed/_pending → .none`: rigid snap — drag left the valid arc
    private func fireHapticIfNeeded(from old: HoverState, to new: HoverState) {
        switch (old, new) {
        case (.pending(let i), .confirmed(let j)) where i == j:
            HapticFeedback.medium()
        case (.none, .confirmed):
            HapticFeedback.medium()
        case (.confirmed(let i), .confirmed(let j)) where i != j:
            HapticFeedback.rigid()
        case (.pending(let i), .pending(let j)) where i != j:
            HapticFeedback.light()
        case (.confirmed, .none), (.pending, .none):
            HapticFeedback.rigid()
        default:
            break
        }
    }

    /// Computes hover state from a global touch point using angle-sector selection.
    ///
    /// - Dead zone (0–52 pt from anchor): returns `.pending` — soft preview, no commit on release.
    /// - Past dead zone (≥52 pt): returns `.confirmed` — full highlight, commits on release.
    /// - Outside the rendered arc or beyond its outer margin: returns `.none`.
    private func computeHoverState(for point: CGPoint) -> HoverState {
        guard let anchor = anchorPosition else { return .none }
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let distance = hypot(dx, dy)

        var angleDeg = atan2(dy, dx) * 180 / .pi
        if angleDeg < 0 { angleDeg += 360 }

        guard distance <= radius + 60,
              let sector = sectorIndex(for: angleDeg) else { return .none }
        return distance < 52 ? .pending(sector) : .confirmed(sector)
    }

    /// Derive equal sectors from the rendered fan so visual and drag targets stay aligned.
    private func sectorIndex(for angleDeg: Double) -> Int? {
        let halfStep = (angles[1] - angles[0]) / 2
        guard angleDeg >= angles[0] - halfStep,
              angleDeg <= angles[angles.count - 1] + halfStep else { return nil }
        return options.indices.min { abs(angles[$0] - angleDeg) < abs(angles[$1] - angleDeg) }
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
