import Foundation
import UniformTypeIdentifiers

struct LoadedShareFile: Sendable {
    let url: URL
    let name: String
    let size: Int64
    var suggestedTitle: String? = nil
    var textPreview: String? = nil
}

enum SharedAttachmentLoader {
    static func load(_ providers: [NSItemProvider]) async throws -> LoadedShareFile {
        guard providers.count == 1, let provider = providers.first else { throw ShareError.singleFileOnly }
        let result: LoadedShareFile
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            result = try await withCheckedThrowingContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    do {
                        if let error { throw error }
                        guard let url = item as? URL, url.isFileURL else { throw ShareError.singleFileOnly }
                        continuation.resume(returning: try copy(url, suggestedName: nil, type: nil))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            result = try await loadText(provider)
        } else {
            guard let identifier = provider.registeredTypeIdentifiers.first(where: {
                guard let type = UTType($0) else { return false }
                return type.conforms(to: .data) && !type.conforms(to: .url) && !type.conforms(to: .directory)
            }) else { throw ShareError.singleFileOnly }
            let suggestedName = provider.suggestedName
            result = try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
                    do {
                        if let error { throw error }
                        guard let url else { throw ShareError.invalidFile }
                        // The provider's temporary URL expires when this callback returns.
                        continuation.resume(returning: try copy(url, suggestedName: suggestedName, type: UTType(identifier)))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: result.url.deletingLastPathComponent())
            throw CancellationError()
        }
        return result
    }

    private static func loadText(_ provider: NSItemProvider) async throws -> LoadedShareFile {
        let text: String = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let attributed = item as? NSAttributedString {
                    continuation.resume(returning: attributed.string)
                } else if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(throwing: ShareError.invalidText)
                }
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ShareError.invalidText }
        return try await Task.detached(priority: .userInitiated) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("payload.txt")
            let bytes = Data(text.utf8)
            do { try bytes.write(to: destination, options: [.atomic, .completeFileProtection]) }
            catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
            let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Shared message"
            return LoadedShareFile(url: destination, name: "Shared message.txt", size: Int64(bytes.count),
                                   suggestedTitle: String(firstLine.trimmingCharacters(in: .whitespaces).prefix(80)),
                                   textPreview: String(text.prefix(2000)))
        }.value
    }

    private static func copy(_ source: URL, suggestedName: String?, type: UTType?) throws -> LoadedShareFile {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ShareError.singleFileOnly }
        var name = ((suggestedName?.isEmpty == false ? suggestedName! : source.lastPathComponent) as NSString).lastPathComponent
        if (name as NSString).pathExtension.isEmpty {
            let ext = source.pathExtension.isEmpty ? type?.preferredFilenameExtension : source.pathExtension
            if let ext, !ext.isEmpty { name += "." + ext }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("payload")
        do { try FileManager.default.copyItem(at: source, to: destination) }
        catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return LoadedShareFile(url: destination, name: name, size: Int64(values.fileSize ?? 0))
    }
}
