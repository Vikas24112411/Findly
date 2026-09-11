import Testing
import Foundation
import SwiftData
import UniformTypeIdentifiers
@testable import Findly

@Suite("Share Inbox")
struct ShareInboxTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func metadata(id: UUID = UUID(), name: String = "photo.heic", tagIDs: [UUID] = [], newTags: [String] = []) -> SharedFile {
        SharedFile(id: id, originalName: name, title: "Shared photo", notes: "Keep this", tagIDs: tagIDs,
                   newTagNames: newTags, createdAt: Date())
    }

    @Test("Only complete packages become visible, preserving exact bytes")
    func atomicPackage() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = ShareInbox(root: root.appendingPathComponent("inbox"))
        let source = root.appendingPathComponent("original.heic")
        let bytes = Data([0, 1, 2, 255])
        try bytes.write(to: source)
        let file = metadata()
        try inbox.enqueue(source: source, file: file)
        let packages = try inbox.packages()
        #expect(packages.count == 1)
        let package = try #require(packages.first)
        #expect(try inbox.read(package).id == file.id)
        #expect(try Data(contentsOf: package.appendingPathComponent("payload")) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(throws: (any Error).self) {
            try inbox.enqueue(source: root.appendingPathComponent("missing"), file: metadata())
        }
        #expect(try inbox.packages().count == 1)
    }

    @Test("Imports keep format and metadata; replay does not duplicate items")
    @MainActor
    func importAndReplay() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = ShareInbox(root: root.appendingPathComponent("inbox"))
        let storage = try LocalFileService(baseDirectory: root.appendingPathComponent("vault"))
        let container = PersistenceController(inMemory: true).container
        let context = container.mainContext
        let tag = Tag(name: "Travel")
        context.insert(tag)
        try context.save()
        let source = root.appendingPathComponent("original.heic")
        let bytes = Data([9, 8, 7])
        try bytes.write(to: source)
        let file = metadata(tagIDs: [tag.id], newTags: ["travel", "New", "New"])
        try inbox.enqueue(source: source, file: file)
        let importer = ShareInboxImporter()
        #expect(try await importer.importFiles(inbox: inbox, container: container, storage: storage, authenticated: false) == 1)
        var items = try ModelContext(container).fetch(FetchDescriptor<Item>())
        let item = try #require(items.first)
        #expect(item.title == file.title)
        #expect(item.itemDescription == file.notes)
        #expect(item.originalFileName == "photo.heic")
        #expect(item.fileType == .image)
        #expect(item.syncStatus == .localOnly)
        #expect(Set(item.tags.map(\.name)) == ["Travel", "New"])
        let path = try #require(item.localFilePath)
        #expect(path.hasSuffix(".heic"))
        #expect(try await storage.read(relativePath: path) == bytes)
        #expect(try inbox.packages().isEmpty)
        // Simulate a process dying after database commit but before package removal.
        try inbox.enqueue(source: source, file: file)
        #expect(try await importer.importFiles(inbox: inbox, container: container, storage: storage, authenticated: true) == 0)
        items = try ModelContext(container).fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        #expect(try inbox.packages().isEmpty)
    }

    @Test("Failed imports remain retryable while other packages import")
    @MainActor
    func failureRetainsFile() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = ShareInbox(root: root.appendingPathComponent("inbox"))
        let storage = try LocalFileService(baseDirectory: root.appendingPathComponent("vault"))
        let container = PersistenceController(inMemory: true).container
        let source = root.appendingPathComponent("original.pdf")
        try Data([1]).write(to: source)
        let broken = metadata(name: "broken.pdf")
        try inbox.enqueue(source: source, file: broken)
        let package = try #require(try inbox.packages().first)
        try FileManager.default.removeItem(at: package.appendingPathComponent("payload"))
        try inbox.enqueue(source: source, file: metadata(name: "valid.pdf"))
        let importer = ShareInboxImporter()
        do {
            _ = try await importer.importFiles(inbox: inbox, container: container, storage: storage, authenticated: true)
            Issue.record("Expected an import failure")
        } catch {}
        #expect(try inbox.packages().count == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Item>()) == 1)
        try FileManager.default.copyItem(at: source, to: package.appendingPathComponent("payload"))
        #expect(try await importer.importFiles(inbox: inbox, container: container, storage: storage, authenticated: true) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Item>()) == 2)
    }

    @Test("Provider temporary files are copied before their callback returns")
    func providerLifetime() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("sample.pdf")
        let bytes = Data("%PDF-example".utf8)
        try bytes.write(to: original)
        let provider = NSItemProvider()
        provider.suggestedName = "Report.pdf"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
            completion(original, false, nil)
            return nil
        }
        let loaded = try await SharedAttachmentLoader.load([provider])
        defer { try? FileManager.default.removeItem(at: loaded.url.deletingLastPathComponent()) }
        try? FileManager.default.removeItem(at: original)
        #expect(loaded.name == "Report.pdf")
        #expect(try Data(contentsOf: loaded.url) == bytes)
    }

    @Test("Web links and multiple attachments are rejected")
    func unsupportedInput() async throws {
        let provider = NSItemProvider(object: NSURL(string: "https://example.com")!)
        for providers in [[provider], [provider, provider], []] {
            do {
                _ = try await SharedAttachmentLoader.load(providers)
                Issue.record("Unsupported input was accepted")
            } catch {}
        }
    }

    @Test("Shared text preserves emoji, whitespace, and links through vault import")
    @MainActor
    func textMessageImport() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let text = "  Meet tomorrow 👋🏽\nతెలుగు message\nhttps://example.com\n  "
        let provider = NSItemProvider(object: text as NSString)
        let loaded = try await SharedAttachmentLoader.load([provider])
        defer { try? FileManager.default.removeItem(at: loaded.url.deletingLastPathComponent()) }
        #expect(loaded.name == "Shared message.txt")
        #expect(loaded.suggestedTitle == "Meet tomorrow 👋🏽")
        #expect(loaded.textPreview == text)
        #expect(try Data(contentsOf: loaded.url) == Data(text.utf8))
        let inbox = ShareInbox(root: root.appendingPathComponent("inbox"))
        let file = metadata(name: loaded.name)
        try inbox.enqueue(source: loaded.url, file: file)
        let storage = try LocalFileService(baseDirectory: root.appendingPathComponent("vault"))
        let container = PersistenceController(inMemory: true).container
        #expect(try await ShareInboxImporter().importFiles(inbox: inbox, container: container, storage: storage, authenticated: false) == 1)
        let item = try #require(try container.mainContext.fetch(FetchDescriptor<Item>()).first)
        #expect(item.fileType == .note)
        let path = try #require(item.localFilePath)
        #expect(try await storage.read(relativePath: path) == Data(text.utf8))
    }

    @Test("Long messages have a bounded preview but retain their full content")
    func longTextMessage() async throws {
        let text = String(repeating: "A long message 🌏\n", count: 500)
        let loaded = try await SharedAttachmentLoader.load([NSItemProvider(object: text as NSString)])
        defer { try? FileManager.default.removeItem(at: loaded.url.deletingLastPathComponent()) }
        #expect(loaded.textPreview?.count == 2000)
        #expect(try Data(contentsOf: loaded.url) == Data(text.utf8))
    }

    @Test("Empty text is rejected")
    func emptyTextMessage() async throws {
        do {
            _ = try await SharedAttachmentLoader.load([NSItemProvider(object: "  \n" as NSString)])
            Issue.record("An empty message was accepted")
        } catch {
            #expect(error is ShareError)
        }
    }

    @Test("Installed extension advertises text as well as files")
    func textActivationRule() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let plistURL = plugins.appendingPathComponent("FindlyShare.appex/Info.plist")
        let plist = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any])
        let extensionInfo = try #require(plist["NSExtension"] as? [String: Any])
        let attributes = try #require(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        let rule = try #require(attributes["NSExtensionActivationRule"] as? String)
        let predicate = NSPredicate(format: rule)
        func accepts(_ identifiers: [String]) -> Bool {
            predicate.evaluate(with: ["extensionItems": [["attachments": identifiers.map { ["registeredTypeIdentifiers": [$0]] }]]])
        }
        #expect(accepts([UTType.utf8PlainText.identifier]))
        #expect(accepts([UTType.plainText.identifier]))
        #expect(accepts([UTType.pdf.identifier]))
        #expect(accepts([UTType.jpeg.identifier]))
        #expect(!accepts([UTType.pdf.identifier, UTType.pdf.identifier]))
        #expect(!accepts([UTType.url.identifier]))
    }

}
