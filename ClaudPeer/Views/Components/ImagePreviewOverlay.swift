import SwiftUI
import AppKit

struct ImagePreviewOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @State private var nsImage: NSImage?
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var isDragging = false

    private let attachment: MessageAttachment?
    private let rawImageData: Data?
    private let rawMediaType: String?

    init(attachment: MessageAttachment) {
        self.attachment = attachment
        self.rawImageData = nil
        self.rawMediaType = nil
    }

    init(imageData: Data, mediaType: String) {
        self.attachment = nil
        self.rawImageData = imageData
        self.rawMediaType = mediaType
    }

    private var imageSize: String {
        guard let nsImage else { return "" }
        let w = Int(nsImage.size.width)
        let h = Int(nsImage.size.height)
        return "\(w) × \(h)"
    }

    private var fileSize: String {
        let bytes: Int
        if let attachment {
            bytes = attachment.fileSize
        } else if let rawImageData {
            bytes = rawImageData.count
        } else {
            return ""
        }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            imageArea
            Divider()
            metadataBar
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(.background)
        .accessibilityIdentifier("imagePreview.overlay")
        .task {
            loadImage()
        }
        .onExitCommand { dismiss() }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityIdentifier("imagePreview.closeButton")
            .accessibilityLabel("Close preview")
            .help("Close (Esc)")

            Spacer()

            HStack(spacing: 12) {
                Button { zoomIn() } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("imagePreview.zoomInButton")
                .accessibilityLabel("Zoom in")
                .help("Zoom in")

                Button { zoomOut() } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("imagePreview.zoomOutButton")
                .accessibilityLabel("Zoom out")
                .help("Zoom out")

                Button { resetZoom() } label: {
                    Text("\(Int(zoom * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(minWidth: 40)
                }
                .buttonStyle(.borderless)
                .help("Reset zoom")

                Divider().frame(height: 16)

                Button { copyToClipboard() } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("imagePreview.copyButton")
                .accessibilityLabel("Copy to clipboard")
                .help("Copy to clipboard")

                if attachment != nil {
                    Button { openInFinder() } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("imagePreview.openInFinderButton")
                    .accessibilityLabel("Show in Finder")
                    .help("Show in Finder")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var imageArea: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: zoom > 1) {
                if let nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoom)
                        .frame(
                            width: max(geo.size.width, geo.size.width * zoom),
                            height: max(geo.size.height, geo.size.height * zoom)
                        )
                } else {
                    VStack {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("Unable to load image")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if zoom > 1 {
                    resetZoom()
                } else {
                    zoom = 2.0
                }
            }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    zoom = max(0.25, min(5.0, value.magnification))
                }
        )
    }

    @ViewBuilder
    private var metadataBar: some View {
        HStack(spacing: 16) {
            if !imageSize.isEmpty {
                Label(imageSize, systemImage: "aspectratio")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !fileSize.isEmpty {
                Label(fileSize, systemImage: "doc")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let attachment {
                Text(attachment.mediaType)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let rawMediaType {
                Text(rawMediaType)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func loadImage() {
        if let attachment {
            nsImage = AttachmentStore.loadNSImage(attachment: attachment)
        } else if let rawImageData {
            nsImage = NSImage(data: rawImageData)
        }
    }

    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.15)) {
            zoom = min(5.0, zoom * 1.5)
        }
    }

    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.15)) {
            zoom = max(0.25, zoom / 1.5)
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.15)) {
            zoom = 1.0
            offset = .zero
        }
    }

    private func copyToClipboard() {
        guard let nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    private func openInFinder() {
        guard let attachment else { return }
        let url = AttachmentStore.url(for: attachment)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

