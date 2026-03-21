import Foundation
import SwiftData

@Model
final class MessageAttachment {
    var id: UUID
    var mediaType: String
    var fileName: String
    var fileSize: Int
    var message: ConversationMessage?

    init(mediaType: String, fileName: String, fileSize: Int, message: ConversationMessage? = nil) {
        self.id = UUID()
        self.mediaType = mediaType
        self.fileName = fileName
        self.fileSize = fileSize
        self.message = message
    }

    var fileExtension: String {
        switch mediaType {
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "text/plain": return "txt"
        case "text/markdown": return "md"
        case "application/pdf": return "pdf"
        default: return "dat"
        }
    }

    var isImage: Bool {
        mediaType.hasPrefix("image/")
    }

    var isDocument: Bool {
        ["text/plain", "text/markdown", "application/pdf"].contains(mediaType)
    }

    var iconName: String {
        switch mediaType {
        case "text/plain", "text/markdown": return "doc.text"
        case "application/pdf": return "doc.richtext"
        default: return isImage ? "photo" : "doc"
        }
    }
}
