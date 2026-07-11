import Foundation
import UniformTypeIdentifiers

enum FileType: String, Codable, CaseIterable, Sendable {
    case image
    case video
    case audio
    case pdf
    case document
    case note
    case link
    case archive
    case other

    // MARK: - Display

    var displayName: String {
        switch self {
        case .image:    return "Image"
        case .video:    return "Video"
        case .audio:    return "Audio"
        case .pdf:      return "PDF"
        case .document: return "Document"
        case .note:     return "Note"
        case .link:     return "Link"
        case .archive:  return "Archive"
        case .other:    return "File"
        }
    }

    var sfSymbol: String {
        switch self {
        case .image:    return "photo"
        case .video:    return "video.fill"
        case .audio:    return "waveform"
        case .pdf:      return "doc.richtext.fill"
        case .document: return "doc.text.fill"
        case .note:     return "note.text"
        case .link:     return "link"
        case .archive:  return "archivebox.fill"
        case .other:    return "doc.fill"
        }
    }

    var addSheetSymbol: String {
        switch self {
        case .image:    return "photo.on.rectangle"
        case .video:    return "video.badge.plus"
        case .audio:    return "mic.fill"
        case .pdf:      return "doc.richtext"
        case .document: return "doc.badge.plus"
        case .note:     return "square.and.pencil"
        case .link:     return "link.badge.plus"
        case .archive:  return "archivebox"
        case .other:    return "folder.badge.plus"
        }
    }

    // MARK: - MIME

    var primaryMimeType: String {
        switch self {
        case .image:    return "image/jpeg"
        case .video:    return "video/mp4"
        case .audio:    return "audio/mpeg"
        case .pdf:      return "application/pdf"
        case .document: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .note:     return "text/plain"
        case .link:     return "text/uri-list"
        case .archive:  return "application/zip"
        case .other:    return "application/octet-stream"
        }
    }

    var fileExtension: String {
        switch self {
        case .image:    return "jpg"
        case .video:    return "mp4"
        case .audio:    return "m4a"
        case .pdf:      return "pdf"
        case .document: return "docx"
        case .note:     return "txt"
        case .link:     return "webloc"
        case .archive:  return "zip"
        case .other:    return "bin"
        }
    }

    // MARK: - Detection

    static func detect(from utType: UTType) -> FileType {
        if utType.conforms(to: .image)   { return .image }
        if utType.conforms(to: .movie) || utType.conforms(to: .video) { return .video }
        if utType.conforms(to: .audio)   { return .audio }
        if utType.conforms(to: .pdf)     { return .pdf }
        if utType.conforms(to: .spreadsheet)
            || utType.conforms(to: .presentation) { return .document }
        if utType.conforms(to: .plainText) || utType.conforms(to: .text) { return .note }
        if utType.conforms(to: .url)     { return .link }
        if utType.conforms(to: .archive) || utType.conforms(to: .zip) { return .archive }
        return .other
    }

    static func detect(mimeType: String) -> FileType {
        let lower = mimeType.lowercased()
        if lower.hasPrefix("image/")                       { return .image }
        if lower.hasPrefix("video/")                       { return .video }
        if lower.hasPrefix("audio/")                       { return .audio }
        if lower == "application/pdf"                      { return .pdf }
        if lower.contains("word") || lower.contains("excel")
            || lower.contains("powerpoint")                { return .document }
        if lower.hasPrefix("text/")                        { return .note }
        if lower.contains("zip") || lower.contains("archive")
            || lower.contains("compressed")               { return .archive }
        return .other
    }

    static func detect(fileExtension ext: String) -> FileType {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff":
            return .image
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv":
            return .video
        case "mp3", "m4a", "aac", "wav", "flac", "ogg":
            return .audio
        case "pdf":
            return .pdf
        case "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key":
            return .document
        case "txt", "md", "markdown", "rtf":
            return .note
        case "url", "webloc":
            return .link
        case "zip", "tar", "gz", "bz2", "7z", "rar":
            return .archive
        default:
            return .other
        }
    }
}
