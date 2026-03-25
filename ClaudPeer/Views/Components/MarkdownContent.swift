import SwiftUI
import MarkdownUI

struct MarkdownContent: View {
    let text: String
    @AppStorage(AppSettings.renderAdmonitionsKey, store: AppSettings.store) private var renderAdmonitions = true

    var body: some View {
        if renderAdmonitions, let blocks = AdmonitionParser.extractBlocks(from: text), !blocks.isEmpty {
            admonitionAwareContent(blocks: blocks)
        } else {
            Markdown(text)
                .markdownTheme(.claudPeer)
                .textSelection(.enabled)
                .xrayId("markdownContent")
        }
    }

    @ViewBuilder
    private func admonitionAwareContent(blocks: [AdmonitionParser.Block]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let md):
                    Markdown(md)
                        .markdownTheme(.claudPeer)
                        .textSelection(.enabled)
                case .admonition(let kind, let title, let body):
                    AdmonitionCardView(kind: kind, title: title, content: body)
                }
            }
        }
        .xrayId("markdownContent")
    }
}

// MARK: - Admonition Parser

enum AdmonitionParser {
    enum Block {
        case markdown(String)
        case admonition(kind: AdmonitionKind, title: String, body: String)
    }

    /// Extract admonition blocks from markdown text, splitting into regular markdown and admonition blocks.
    static func extractBlocks(from text: String) -> [Block]? {
        let pattern = #"(?:^|\n)> \[!(note|tip|info|success|warning|caution|error|danger|bug|example|quote|important|abstract)\](?: (.+))?\n((?:> .*(?:\n|$))*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return nil }

        var blocks: [Block] = []
        var lastEnd = 0

        for match in matches {
            let matchStart = match.range.location
            // Include the newline before the match if present
            let leadingNewline = matchStart > 0 && nsText.character(at: matchStart) != Character("\n").asciiValue.map(UInt16.init) ?? 0
            _ = leadingNewline

            if matchStart > lastEnd {
                let prefix = nsText.substring(with: NSRange(location: lastEnd, length: matchStart - lastEnd))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    blocks.append(.markdown(prefix))
                }
            }

            let kindStr = nsText.substring(with: match.range(at: 1)).lowercased()
            let kind = AdmonitionKind(rawValue: kindStr) ?? .note
            let title = match.range(at: 2).location != NSNotFound
                ? nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                : ""
            let rawBody = nsText.substring(with: match.range(at: 3))
            let body = rawBody
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line in
                    let s = String(line)
                    if s.hasPrefix("> ") { return String(s.dropFirst(2)) }
                    if s == ">" { return "" }
                    return s
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            blocks.append(.admonition(kind: kind, title: title, body: body))
            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsText.length {
            let suffix = nsText.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !suffix.isEmpty {
                blocks.append(.markdown(suffix))
            }
        }

        return blocks
    }
}

// MARK: - Admonition Kind

enum AdmonitionKind: String {
    case note, tip, info, success, warning, caution, error, danger, bug, example, quote, important, abstract

    var icon: String {
        switch self {
        case .note: "pencil.circle.fill"
        case .tip: "lightbulb.fill"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning, .caution: "exclamationmark.triangle.fill"
        case .error, .danger, .bug: "xmark.circle.fill"
        case .example: "doc.text.fill"
        case .quote: "quote.opening"
        case .important: "exclamationmark.circle.fill"
        case .abstract: "list.bullet.rectangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .note: .blue
        case .tip: .cyan
        case .info: .blue
        case .success: .green
        case .warning, .caution: .orange
        case .error, .danger, .bug: .red
        case .example: .purple
        case .quote: .gray
        case .important: .orange
        case .abstract: .indigo
        }
    }

    var defaultTitle: String {
        rawValue.capitalized
    }
}

// MARK: - Admonition Card View

struct AdmonitionCardView: View {
    let kind: AdmonitionKind
    let title: String
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.color)
                .font(.system(size: 14))
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? kind.defaultTitle : title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(kind.color)

                if !content.isEmpty {
                    Markdown(content)
                        .markdownTheme(.claudPeer)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(kind.color.opacity(0.4))
                .frame(width: 3)
        }
        .xrayId("admonitionCard.\(kind.rawValue)")
    }
}

extension Theme {
    @MainActor
    static let claudPeer = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(14)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(.secondary)
            BackgroundColor(Color(.textBackgroundColor).opacity(0.5))
        }
        .link {
            ForegroundColor(.accentColor)
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(24)
                }
                .markdownMargin(top: 16, bottom: 8)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(20)
                }
                .markdownMargin(top: 14, bottom: 6)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(17)
                }
                .markdownMargin(top: 12, bottom: 4)
        }
        .paragraph { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 0, bottom: 8)
        }
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle {
                    FontStyle(.italic)
                    ForegroundColor(.secondary)
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: 3)
                }
                .markdownMargin(top: 4, bottom: 8)
        }
        .codeBlock { configuration in
            CodeBlockView(configuration: configuration)
                .markdownMargin(top: 4, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.2))
        }
        .thematicBreak {
            Divider()
                .markdownMargin(top: 12, bottom: 12)
        }
        .image { configuration in
            configuration.label
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .markdownMargin(top: 4, bottom: 8)
        }
        .table { configuration in
            configuration.label
                .markdownTableBorderStyle(.init(color: .secondary.opacity(0.3)))
                .markdownMargin(top: 4, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
}
