import Foundation

struct SharedTag: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    var colorHex: String? = nil
    var sfSymbol: String? = nil
}

struct ShareCatalog: Codable, Sendable {
    let tags: [SharedTag]
    let requiresUnlock: Bool
    var appearanceMode: String? = nil
}

struct SharedFile: Codable, Identifiable, Sendable {
    let id: UUID
    let originalName: String
    let title: String
    let notes: String
    let tagIDs: [UUID]
    let newTagNames: [String]
    let createdAt: Date
}

/// A package is visible to the app only after its atomic move into Ready.
/// The extension never opens the app's database or custom-folder bookmark.
struct ShareInbox: Sendable {
    static let groupID = "group.com.findlyvikas.app"
    let root: URL

    init(root: URL) { self.root = root }

    init() throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupID
        ) else { throw ShareError.unavailable }
        root = container.appendingPathComponent("ShareInbox", isDirectory: true)
    }

    var readyDirectory: URL { root.appendingPathComponent("Ready", isDirectory: true) }

    func prepare() throws {
        try FileManager.default.createDirectory(at: readyDirectory, withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    func catalog() throws -> ShareCatalog {
        try JSONDecoder().decode(ShareCatalog.self, from: Data(contentsOf: root.appendingPathComponent("catalog.json")))
    }

    func publish(_ catalog: ShareCatalog) throws {
        try prepare()
        try JSONEncoder().encode(catalog).write(to: root.appendingPathComponent("catalog.json"), options: [.atomic, .completeFileProtection])
    }

    func enqueue(source: URL, file: SharedFile) throws {
        try prepare()
        let staging = root.appendingPathComponent("staging-\(file.id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent("payload"))
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: staging.appendingPathComponent("payload").path)
        try JSONEncoder().encode(file).write(to: staging.appendingPathComponent("metadata.json"), options: [.atomic, .completeFileProtection])
        try FileManager.default.moveItem(at: staging, to: readyDirectory.appendingPathComponent(file.id.uuidString))
    }

    func packages() throws -> [URL] {
        try prepare()
        return try FileManager.default.contentsOfDirectory(at: readyDirectory, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func read(_ package: URL) throws -> SharedFile {
        let file = try JSONDecoder().decode(SharedFile.self, from: Data(contentsOf: package.appendingPathComponent("metadata.json")))
        guard file.id.uuidString == package.lastPathComponent,
              file.originalName == (file.originalName as NSString).lastPathComponent,
              !file.originalName.isEmpty else { throw ShareError.invalidFile }
        return file
    }
}

enum ShareError: LocalizedError {
    case unavailable, singleFileOnly, invalidFile, invalidText

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Findly sharing is unavailable. Open Findly once, then try sharing again."
        case .singleFileOnly: return "Share one file or text message at a time. Web links and folders aren’t supported yet."
        case .invalidText: return "This message is empty or couldn’t be read. Try sharing it again as plain text."
        case .invalidFile: return "This file couldn’t be read. Try sharing it again from the original app."
        }
    }
}
