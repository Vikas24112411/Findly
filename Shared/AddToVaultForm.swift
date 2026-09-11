import SwiftUI
import ImageIO

/// Shared presentation for in-app imports and the share extension.
/// Callers own persistence; neither SwiftData nor the extension context belongs here.
struct AddToVaultForm: View {
    let fileName: String
    let fileType: FileType
    let previewImage: UIImage?
    var textPreview: String? = nil
    @Binding var title: String
    @Binding var notes: String
    @Binding var showNotes: Bool
    let selectedTags: [VaultTagOption]
    var isSaving = false
    var isSaved = false
    var footer: String? = nil
    let addTag: () -> Void
    let removeTag: (UUID) -> Void
    let save: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xLarge) {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: fileType == .image || textPreview != nil || !dynamicTypeSize.isAccessibilitySize ? 240 : nil)
                    .frame(minHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xLarge, style: .continuous))
                    .padding(.horizontal, AppTheme.Spacing.base)

                VStack(spacing: AppTheme.Spacing.medium) {
                    card {
                        TextField("Title", text: $title)
                            .font(AppTheme.Typography.title3)
                            .accessibilityIdentifier("vault.title")
                    }
                    card {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                                tagLabel
                                addTagButton
                            }
                        } else {
                            HStack {
                                tagLabel
                                Spacer()
                                addTagButton
                            }
                        }
                        if !selectedTags.isEmpty {
                            VaultTagFlowLayout(spacing: AppTheme.Spacing.small) {
                                ForEach(selectedTags.sorted { $0.name < $1.name }) { tag in
                                    VaultTagChip(tag: tag) { removeTag(tag.id) }
                                }
                            }
                        }
                    }
                    if showNotes {
                        card {
                            TextEditor(text: $notes)
                                .font(AppTheme.Typography.body)
                                .frame(minHeight: 120)
                                .scrollContentBackground(.hidden)
                                .accessibilityLabel("Notes")
                                .accessibilityIdentifier("vault.notes")
                        }
                    } else {
                        Button {
                            withAnimation(reduceMotion ? nil : AppTheme.Animation.fast) { showNotes = true }
                        } label: {
                            Label("Add notes", systemImage: "plus.circle")
                                .font(AppTheme.Typography.subheadline)
                                .frame(minHeight: 44)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Spacing.base)
                    }
                    if let footer {
                        Text(footer)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppTheme.Spacing.base)
                    }
                }
                .padding(.bottom, AppTheme.Spacing.base)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text("Save")
                    .font(AppTheme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.small)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || isSaved)
            .accessibilityIdentifier("vault.save")
            .padding(.horizontal, AppTheme.Spacing.base)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(AppTheme.Colors.groupedBG)
        }
        .disabled(isSaving || isSaved)
        .tint(AppTheme.Colors.accent)
        .background(AppTheme.Colors.groupedBG)
    }

    private var tagLabel: some View {
        Text("Tags")
            .font(AppTheme.Typography.subheadline)
            .foregroundStyle(AppTheme.Colors.secondaryLabel)
    }

    private var addTagButton: some View {
        Button("Add Tag", action: addTag)
            .font(AppTheme.Typography.subheadline)
            .frame(minHeight: 44)
            .accessibilityIdentifier("vault.addTag")
    }

    private var preview: some View {
        ZStack {
            AppTheme.Colors.secondaryBG
            if let textPreview {
                ScrollView {
                    Text(textPreview)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.base)
                        .textSelection(.enabled)
                }
                .accessibilityLabel("Shared message preview")
            } else if fileType == .image, let previewImage {
                GeometryReader { geometry in
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .accessibilityLabel("Preview of \(fileName)")
            } else {
                VStack(spacing: AppTheme.Spacing.medium) {
                    Image(systemName: fileType.sfSymbol)
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(fileType.tintColor)
                        .accessibilityHidden(true)
                    Text(fileName)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small, content: content)
            .padding(AppTheme.Spacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.secondaryBG)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
            .padding(.horizontal, AppTheme.Spacing.base)
    }
}

struct VaultSavingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: AppTheme.Spacing.medium) {
                ProgressView().scaleEffect(1.5).tint(AppTheme.Colors.accent)
                Text("Saving to vault…")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.label)
            }
            .padding(AppTheme.Spacing.xLarge)
            .background(AppTheme.Colors.secondaryBG, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        }
    }
}

struct VaultSavedToast: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.Colors.syncSynced)
            Text("Saved!").font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(AppTheme.Colors.label)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.Colors.secondaryBG, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Bounded decoding from disk keeps large WhatsApp images out of extension memory.
enum VaultPreview {
    static func image(at url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 800,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
