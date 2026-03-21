import SwiftUI
import AppKit

struct AttachmentThumbnail: View {
    let attachment: MessageAttachment
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if attachment.isImage {
                imageThumbnail
            } else {
                documentThumbnail
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(attachment.isImage ? "Image attachment" : "File: \(attachment.fileName)")
        .task {
            if attachment.isImage {
                nsImage = AttachmentStore.loadNSImage(attachment: attachment)
            }
        }
    }

    @ViewBuilder
    private var imageThumbnail: some View {
        if let nsImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 80, maxWidth: 280, minHeight: 60, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 120, height: 80)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }

    @ViewBuilder
    private var documentThumbnail: some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.iconName)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }

    private var formattedSize: String {
        let bytes = attachment.fileSize
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}
