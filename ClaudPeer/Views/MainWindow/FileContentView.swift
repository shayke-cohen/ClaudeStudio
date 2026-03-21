import SwiftUI
import AppKit

enum FileViewMode: String, CaseIterable, Identifiable {
    case preview = "Preview"
    case source = "Source"
    case diff = "Diff"

    var id: String { rawValue }
}

struct FileContentView: View {
    let node: FileNode
    let rootURL: URL
    let onBack: () -> Void

    @State private var viewMode: FileViewMode = .source
    @State private var fileContent: String?
    @State private var diffContent: String?
    @State private var diffSummary: (added: Int, removed: Int) = (0, 0)
    @State private var isBinary = false
    @State private var isLoading = true

    private var isMarkdown: Bool {
        FileSystemService.isMarkdownFile(node.name)
    }

    private var hasDiff: Bool {
        node.gitStatus != nil
    }

    private var availableModes: [FileViewMode] {
        var modes: [FileViewMode] = []
        if isMarkdown { modes.append(.preview) }
        modes.append(.source)
        if hasDiff { modes.append(.diff) }
        return modes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            metadataBar
            if availableModes.count > 1 {
                modePicker
                Divider()
            }
            contentArea
            Divider()
            actionBar
        }
        .task { await loadContent() }
        .onChange(of: node.id) { _, _ in Task { await loadContent() } }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Back to file tree")
            .accessibilityIdentifier("inspector.fileContent.backButton")
            .accessibilityLabel("Back to file tree")

            Image(systemName: FileSystemService.fileIcon(for: node.fileExtension))
                .foregroundStyle(.secondary)
                .font(.caption)

            Text(node.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("inspector.fileContent.fileName")

            Spacer()

            if let status = node.gitStatus {
                gitBadge(status)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Metadata

    private var metadataBar: some View {
        HStack(spacing: 6) {
            if viewMode == .diff, hasDiff {
                Text(node.gitStatus?.label ?? "Changed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if diffSummary.added > 0 {
                    Text("+\(diffSummary.added)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if diffSummary.removed > 0 {
                    Text("-\(diffSummary.removed)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            } else {
                Text(FileSystemService.formatFileSize(node.size))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Text(node.fileExtension.isEmpty ? "file" : node.fileExtension)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let date = node.modifiedDate {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .accessibilityIdentifier("inspector.fileContent.metadataBar")
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            ForEach(availableModes) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityIdentifier("inspector.fileContent.modePicker")
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("inspector.fileContent.loading")
        } else if isBinary {
            binaryPlaceholder
        } else {
            switch viewMode {
            case .preview:
                markdownPreview
            case .source:
                sourceView
            case .diff:
                diffView
            }
        }
    }

    @ViewBuilder
    private var markdownPreview: some View {
        if let content = fileContent {
            ScrollView {
                MarkdownContent(text: content)
                    .padding(10)
            }
            .accessibilityIdentifier("inspector.fileContent.markdownPreview")
        } else {
            emptyContentPlaceholder
        }
    }

    @ViewBuilder
    private var sourceView: some View {
        if let content = fileContent {
            let lang = FileSystemService.languageForExtension(node.fileExtension)
            HighlightedCodeView(code: content, language: lang, showLineNumbers: true)
                .accessibilityIdentifier("inspector.fileContent.sourceView")
        } else {
            emptyContentPlaceholder
        }
    }

    @ViewBuilder
    private var diffView: some View {
        if let diff = diffContent, !diff.isEmpty {
            ScrollView([.horizontal, .vertical]) {
                DiffTextView(diffText: diff)
                    .padding(8)
            }
            .accessibilityIdentifier("inspector.fileContent.diffView")
        } else if node.gitStatus == .untracked, let content = fileContent {
            ScrollView([.horizontal, .vertical]) {
                DiffTextView(diffText: allAddedDiff(content))
                    .padding(8)
            }
            .accessibilityIdentifier("inspector.fileContent.diffView")
        } else {
            ContentUnavailableView("No Changes", systemImage: "checkmark.circle", description: Text("This file has no uncommitted changes."))
        }
    }

    private var binaryPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Binary File")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(FileSystemService.formatFileSize(node.size))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Open in Default App") {
                NSWorkspace.shared.open(node.url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("inspector.fileContent.binaryPlaceholder")
    }

    private var emptyContentPlaceholder: some View {
        ContentUnavailableView("Unable to Read", systemImage: "exclamationmark.triangle", description: Text("Could not read file contents."))
            .accessibilityIdentifier("inspector.fileContent.emptyPlaceholder")
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                NSWorkspace.shared.open(node.url)
            } label: {
                Label("Open in Editor", systemImage: "pencil.and.outline")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Open in default editor")
            .accessibilityIdentifier("inspector.fileContent.openInEditorButton")

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.clipboard")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Copy file path to clipboard")
            .accessibilityIdentifier("inspector.fileContent.copyPathButton")

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func loadContent() async {
        isLoading = true

        let nodeURL = node.url
        let relPath = relativePath
        let root = rootURL
        let wantDiff = hasDiff

        let result = await Task.detached { () -> (Bool, String?, String?, Int, Int) in
            let binary = FileSystemService.isBinaryFile(at: nodeURL)
            let content = binary ? nil : FileSystemService.readFileContents(at: nodeURL)
            let diff = wantDiff ? GitService.fullDiff(file: relPath, in: root) : nil
            let summary = wantDiff ? GitService.diffSummary(file: relPath, in: root) : (0, 0)
            return (binary, content, diff, summary.0, summary.1)
        }.value

        isBinary = result.0
        fileContent = result.1
        diffContent = result.2
        diffSummary = (added: result.3, removed: result.4)

        if isMarkdown && !isBinary {
            viewMode = .preview
        } else {
            viewMode = .source
        }

        isLoading = false
    }

    private var relativePath: String {
        let full = node.url.path
        let root = rootURL.path
        if full.hasPrefix(root) {
            return String(full.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return node.name
    }

    private func allAddedDiff(_ content: String) -> String {
        content.components(separatedBy: "\n").map { "+ \($0)" }.joined(separator: "\n")
    }

    @ViewBuilder
    private func gitBadge(_ status: GitFileStatus) -> some View {
        Circle()
            .fill(colorForStatus(status))
            .frame(width: 7, height: 7)
            .help(status.label)
    }

    private func colorForStatus(_ status: GitFileStatus) -> Color {
        switch status {
        case .modified:  return .orange
        case .added:     return .green
        case .deleted:   return .red
        case .renamed:   return .blue
        case .untracked: return .gray
        case .copied:    return .teal
        }
    }
}

// MARK: - Diff Text View

struct DiffTextView: NSViewRepresentable {
    let diffText: String
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        applyDiff(to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if diffText != context.coordinator.lastDiff {
            applyDiff(to: textView)
            context.coordinator.lastDiff = diffText
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func applyDiff(to textView: NSTextView) {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let lines = diffText.components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            var attrs: [NSAttributedString.Key: Any] = [.font: font]

            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                attrs[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.15)
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.15)
            } else if line.hasPrefix("@@") {
                attrs[.backgroundColor] = NSColor.systemBlue.withAlphaComponent(0.08)
                attrs[.foregroundColor] = NSColor.secondaryLabelColor
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("---") || line.hasPrefix("+++") {
                attrs[.foregroundColor] = NSColor.secondaryLabelColor
            }

            result.append(NSAttributedString(string: line, attributes: attrs))
            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            }
        }

        textView.textStorage?.setAttributedString(result)
    }

    final class Coordinator {
        var textView: NSTextView?
        var lastDiff: String?
    }
}
