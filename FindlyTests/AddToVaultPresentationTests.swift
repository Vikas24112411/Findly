import Testing
import SwiftUI
import UIKit
@testable import Findly

@Suite("Add to Vault Presentation")
@MainActor
struct AddToVaultPresentationTests {
    @Test("Old share catalogs still decode after adding tag styling")
    func legacyCatalog() throws {
        let id = UUID()
        let json = "{\"tags\":[{\"id\":\"\(id.uuidString)\",\"name\":\"Work\"}],\"requiresUnlock\":false}"
        let catalog = try JSONDecoder().decode(ShareCatalog.self, from: Data(json.utf8))
        #expect(catalog.tags.first?.id == id)
        #expect(catalog.tags.first?.colorHex == nil)
        #expect(catalog.appearanceMode == nil)
    }

    @Test("Photo previews are bounded instead of decoding full-size images")
    func boundedPreview() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let input = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1600), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try #require(input.pngData()).write(to: url)
        let preview = try #require(VaultPreview.image(at: url)?.cgImage)
        #expect(max(preview.width, preview.height) <= 800)
        #expect(preview.width > preview.height)
    }

    @Test("Shared form renders at compact and accessible sizes", arguments: [ColorScheme.light, .dark])
    func renderForm(scheme: ColorScheme) async throws {
        for typeSize in [DynamicTypeSize.large, .accessibility5] {
            let tags = [VaultTagOption(id: UUID(), name: "Travel documents and reservations", colorHex: "#3498DB", sfSymbol: "airplane")]
            let content = AddToVaultForm(
                fileName: "Travel itinerary and hotel confirmation for September.pdf", fileType: .pdf, previewImage: nil,
                title: .constant("Travel itinerary"), notes: .constant("Keep for the trip"), showNotes: .constant(false),
                selectedTags: tags, addTag: {}, removeTag: { _ in }, save: {}
            )
            .frame(width: 320, height: 640)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, typeSize)
            let image = try await snapshot(content, scheme: scheme)
            #expect(image.size == CGSize(width: 320, height: 640))
            Attachment.record(try #require(image.pngData()), named: "vault-form-\(scheme)-\(typeSize).png")
        }
    }

    @Test("Shared tag picker renders selected, long, and emoji tags", arguments: [ColorScheme.light, .dark])
    func renderPicker(scheme: ColorScheme) async throws {
        let tag = VaultTagOption(id: UUID(), name: "Travel documents and reservations", colorHex: "#3498DB", sfSymbol: "✈️")
        let content = VaultTagPicker(tags: [tag], selectedIDs: .constant([tag.id]), createTag: { _ in })
            .frame(width: 320, height: 640)
            .environment(\.colorScheme, scheme)
        let image = try await snapshot(content, scheme: scheme)
        Attachment.record(try #require(image.pngData()), named: "vault-picker-\(scheme).png")
    }

    @Test("Shared message uses the existing save form with a readable preview")
    func renderSharedMessage() async throws {
        let content = AddToVaultForm(
            fileName: "Shared message.txt", fileType: .note, previewImage: nil,
            textPreview: "Meet tomorrow 👋🏽\n\nPlease bring the travel documents.\nhttps://example.com",
            title: .constant("Meet tomorrow 👋🏽"), notes: .constant(""), showNotes: .constant(false),
            selectedTags: [], addTag: {}, removeTag: { _ in }, save: {}
        )
        .frame(width: 320, height: 640)
        .environment(\.colorScheme, .light)
        let image = try await snapshot(content, scheme: .light)
        Attachment.record(try #require(image.pngData()), named: "vault-shared-message.png")
    }

    private func snapshot<V: View>(_ content: V, scheme: ColorScheme) async throws -> UIImage {
        // ImageRenderer does not render ScrollView content; use a hosted UIKit snapshot.
        let controller = UIHostingController(rootView: content)
        controller.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // Allow SwiftUI's hosted scroll hierarchy to complete its initial layout.
        try await Task.sleep(for: .milliseconds(150))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

}
