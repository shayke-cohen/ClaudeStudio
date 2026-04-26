import Foundation
import AppKit
import UniformTypeIdentifiers

struct AttachmentStore {
    static let baseDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".odyssey/attachments", isDirectory: true)
    }()

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    static func save(data: Data, mediaType: String, fileName: String? = nil) -> MessageAttachment {
        ensureDirectory()
        let resolvedName = fileName ?? defaultFileName(for: mediaType)
        let attachment = MessageAttachment(
            mediaType: mediaType,
            fileName: resolvedName,
            fileSize: data.count
        )
        let fileURL = url(for: attachment)
        try? data.write(to: fileURL, options: .atomic)
        return attachment
    }

    /// Returns the same `MessageAttachment` record `save(...)` would, but
    /// schedules the actual disk write on a detached Task so the caller's
    /// run loop (typically the main thread reacting to `sessionResult`)
    /// doesn't block on `Data.write`. The file is on disk by the next
    /// time the user opens the attachment — Inspector, image preview,
    /// etc. all gate on a successful read so the brief gap is invisible.
    static func saveDeferred(data: Data, mediaType: String, fileName: String? = nil) -> MessageAttachment {
        ensureDirectory()
        let resolvedName = fileName ?? defaultFileName(for: mediaType)
        let attachment = MessageAttachment(
            mediaType: mediaType,
            fileName: resolvedName,
            fileSize: data.count
        )
        let fileURL = url(for: attachment)
        Task.detached(priority: .utility) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return attachment
    }

    static func load(attachment: MessageAttachment) -> Data? {
        let fileURL = url(for: attachment)
        return try? Data(contentsOf: fileURL)
    }

    static func loadNSImage(attachment: MessageAttachment) -> NSImage? {
        guard attachment.isImage, let data = load(attachment: attachment) else { return nil }
        return NSImage(data: data)
    }

    static func loadText(attachment: MessageAttachment) -> String? {
        guard attachment.mediaType == "text/plain" || attachment.mediaType == "text/markdown" else { return nil }
        guard let data = load(attachment: attachment) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func url(for attachment: MessageAttachment) -> URL {
        baseDirectory.appendingPathComponent("\(attachment.id.uuidString).\(attachment.fileExtension)")
    }

    static func delete(attachment: MessageAttachment) {
        let fileURL = url(for: attachment)
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func base64(for attachment: MessageAttachment) -> String? {
        guard let data = load(attachment: attachment) else { return nil }
        return data.base64EncodedString()
    }

    static func mediaTypeFromNSImage(_ image: NSImage) -> (Data, String)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return (pngData, "image/png")
    }

    static func mediaTypeFromData(_ data: Data) -> String {
        guard data.count >= 4 else { return "application/octet-stream" }
        let header = [UInt8](data.prefix(4))
        if header[0] == 0x89 && header[1] == 0x50 { return "image/png" }
        if header[0] == 0xFF && header[1] == 0xD8 { return "image/jpeg" }
        if header[0] == 0x47 && header[1] == 0x49 { return "image/gif" }
        if header[0] == 0x52 && header[1] == 0x49 { return "image/webp" }
        if header[0] == 0x25 && header[1] == 0x50 && header[2] == 0x44 && header[3] == 0x46 {
            return "application/pdf"
        }
        return "application/octet-stream"
    }

    static func mediaTypeForURL(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "txt": return "text/plain"
        case "md", "markdown": return "text/markdown"
        case "pdf": return "application/pdf"
        default:
            return "application/octet-stream"
        }
    }

    private static let maxImageSize = 5 * 1024 * 1024
    private static let maxDocumentSize = 10 * 1024 * 1024

    static func validate(data: Data, mediaType: String? = nil) -> Bool {
        guard data.count > 0 else { return false }
        if let mt = mediaType, !mt.hasPrefix("image/") {
            return data.count <= maxDocumentSize
        }
        return data.count <= maxImageSize
    }

    static let markdown = UTType("net.daringfireball.markdown") ?? .plainText

    static let supportedContentTypes: [UTType] = [
        .png, .jpeg, .gif, .webP,
        .plainText, .utf8PlainText,
        markdown,
        .pdf,
    ]

    static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp",
        "txt", "md", "markdown",
        "pdf",
    ]

    private static func defaultFileName(for mediaType: String) -> String {
        switch mediaType {
        case "image/png": return "image.png"
        case "image/jpeg": return "image.jpg"
        case "image/gif": return "image.gif"
        case "image/webp": return "image.webp"
        case "text/plain": return "document.txt"
        case "text/markdown": return "document.md"
        case "application/pdf": return "document.pdf"
        default: return "file.dat"
        }
    }
}
