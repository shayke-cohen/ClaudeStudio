// Sources/OdysseyCore/Views/MarkdownContentCore.swift
import SwiftUI
import MarkdownUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Cross-platform shim for LocalFileReferenceSupport
// On iOS, we only need `localReferenceString(from:)` for URL handling.
// The full Mac implementation lives in the main Odyssey target.
public enum LocalFileReferenceSupport {
    public static func localReferenceString(from url: URL) -> String? {
        guard url.isFileURL else { return nil }
        return url.absoluteString
    }
}

// MARK: - MarkdownContentCore

public struct MarkdownContentCore: View {
    public let text: String
    public var renderAdmonitions: Bool = true
    public var onOpenLocalReference: ((String) -> Void)? = nil

    @Environment(\.appTextScale) private var appTextScale

    public init(
        text: String,
        renderAdmonitions: Bool = true,
        onOpenLocalReference: ((String) -> Void)? = nil
    ) {
        self.text = text
        self.renderAdmonitions = renderAdmonitions
        self.onOpenLocalReference = onOpenLocalReference
    }

    private var renderedText: String {
        LocalFileReferenceLinkifier.linkify(text)
    }

    public var body: some View {
        Group {
            if renderAdmonitions, let blocks = AdmonitionParser.extractBlocks(from: renderedText), !blocks.isEmpty {
                admonitionAwareContent(blocks: blocks)
            } else {
                Markdown(renderedText)
                    .markdownTheme(.odysseyCore(scale: appTextScale))
                    .textSelection(.enabled)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            handleOpenURL(url)
        })
    }

    @ViewBuilder
    private func admonitionAwareContent(blocks: [AdmonitionParser.Block]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let md):
                    Markdown(md)
                        .markdownTheme(.odysseyCore(scale: appTextScale))
                        .textSelection(.enabled)
                case .admonition(let kind, let title, let body):
                    AdmonitionCardViewCore(kind: kind, title: title, content: body)
                }
            }
        }
    }

    private func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
        if let reference = LocalFileReferenceSupport.localReferenceString(from: url),
           let onOpenLocalReference {
            onOpenLocalReference(reference)
            return .handled
        }

#if os(macOS)
        NSWorkspace.shared.open(url)
#else
        UIApplication.shared.open(url)
#endif
        return .handled
    }
}

// MARK: - LocalFileReferenceLinkifier (cross-platform, pure Swift/Foundation)

public enum LocalFileReferenceLinkifier {
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)]}")

    public static func linkify(_ text: String) -> String {
        var isInsideFence = false
        let lines = text.components(separatedBy: "\n")
        let transformedLines = lines.map { line -> String in
            if isFenceDelimiter(line) {
                isInsideFence.toggle()
                return line
            }
            guard !isInsideFence else { return line }
            return linkifyInline(line)
        }
        return transformedLines.joined(separator: "\n")
    }

    private static func linkifyInline(_ line: String) -> String {
        var result = ""
        var index = line.startIndex

        while index < line.endIndex {
            if line[index] == "`", let range = inlineCodeRange(in: line, from: index) {
                result += String(line[range])
                index = range.upperBound
                continue
            }

            if let range = markdownLinkRange(in: line, from: index) {
                result += String(line[range])
                index = range.upperBound
                continue
            }

            if let match = nextLocalReference(in: line, from: index), match.range.lowerBound == index {
                result += markdownLink(display: match.reference, destination: match.destination)
                result += match.trailing
                index = match.range.upperBound
                continue
            }

            result.append(line[index])
            index = line.index(after: index)
        }

        return result
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func inlineCodeRange(in text: String, from index: String.Index) -> Range<String.Index>? {
        guard text[index] == "`" else { return nil }
        guard let end = text[text.index(after: index)...].firstIndex(of: "`") else {
            return index..<text.endIndex
        }
        return index..<text.index(after: end)
    }

    private static func markdownLinkRange(in text: String, from index: String.Index) -> Range<String.Index>? {
        guard text[index] == "[" else { return nil }
        guard let closingBracket = text[index...].firstIndex(of: "]") else { return nil }
        let afterBracket = text.index(after: closingBracket)
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }
        guard let closingParen = text[afterBracket...].firstIndex(of: ")") else { return nil }
        return index..<text.index(after: closingParen)
    }

    private static func nextLocalReference(
        in text: String,
        from index: String.Index
    ) -> (range: Range<String.Index>, reference: String, destination: String, trailing: String)? {
        let remaining = String(text[index...])

        if (remaining.hasPrefix("https://") || remaining.hasPrefix("http://")),
           hasReferenceBoundary(in: text, at: index) {
            return matchWebURL(in: text, from: index)
        }

        if remaining.hasPrefix("file://"), hasReferenceBoundary(in: text, at: index) {
            return matchToken(in: text, from: index, allowFileScheme: true)
        }

        if remaining.hasPrefix("/"), hasReferenceBoundary(in: text, at: index) {
            return matchToken(in: text, from: index, allowFileScheme: false)
        }

        return nil
    }

    private static func matchWebURL(
        in text: String,
        from index: String.Index
    ) -> (range: Range<String.Index>, reference: String, destination: String, trailing: String)? {
        let disallowedScalars = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "<>[]{}()|\"'"))
        var end = index
        while end < text.endIndex,
              let scalar = text[end].unicodeScalars.first,
              !disallowedScalars.contains(scalar) {
            end = text.index(after: end)
        }

        guard end > index else { return nil }

        let rawToken = String(text[index..<end])
        let (candidate, trailing) = splitTrailingPunctuation(from: rawToken)
        guard !candidate.isEmpty,
              let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return (
            range: index..<end,
            reference: candidate,
            destination: candidate,
            trailing: trailing
        )
    }

    private static func matchToken(
        in text: String,
        from index: String.Index,
        allowFileScheme: Bool
    ) -> (range: Range<String.Index>, reference: String, destination: String, trailing: String)? {
        let disallowedScalars = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "<>[]{}()|\"'"))
        var end = index
        while end < text.endIndex,
              let scalar = text[end].unicodeScalars.first,
              !disallowedScalars.contains(scalar) {
            end = text.index(after: end)
        }

        guard end > index else { return nil }

        let rawToken = String(text[index..<end])
        let (candidate, trailing) = splitTrailingPunctuation(from: rawToken)
        guard !candidate.isEmpty else { return nil }

        if allowFileScheme {
            guard let url = URL(string: candidate), url.isFileURL else { return nil }
            return (
                range: index..<end,
                reference: candidate,
                destination: url.absoluteString,
                trailing: trailing
            )
        }

        guard candidate.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: candidate)
        return (
            range: index..<end,
            reference: candidate,
            destination: url.absoluteString,
            trailing: trailing
        )
    }

    private static func splitTrailingPunctuation(from token: String) -> (String, String) {
        var reference = token
        var trailing = ""

        while let scalar = reference.unicodeScalars.last,
              trailingPunctuation.contains(scalar) {
            trailing = String(reference.removeLast()) + trailing
        }

        return (reference, trailing)
    }

    private static func markdownLink(display: String, destination: String) -> String {
        let escapedDisplay = display
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "[\(escapedDisplay)](\(destination))"
    }

    private static func hasReferenceBoundary(in text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else { return true }
        let previousIndex = text.index(before: index)
        let previousCharacter = text[previousIndex]
        return previousCharacter.isWhitespace || "([{\"'".contains(previousCharacter)
    }
}

// MARK: - Admonition Parser

public enum AdmonitionParser {
    public enum Block {
        case markdown(String)
        case admonition(kind: AdmonitionKind, title: String, body: String)
    }

    /// Extract admonition blocks from markdown text, splitting into regular markdown and admonition blocks.
    public static func extractBlocks(from text: String) -> [Block]? {
        let pattern = #"(?:^|\n)> \[!(note|tip|info|success|warning|caution|error|danger|bug|example|quote|important|abstract)\](?: (.+))?\n((?:> .*(?:\n|$))*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return nil }

        var blocks: [Block] = []
        var lastEnd = 0

        for match in matches {
            let matchStart = match.range.location
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

public enum AdmonitionKind: String {
    case note, tip, info, success, warning, caution, error, danger, bug, example, quote, important, abstract

    public var icon: String {
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

    public var color: Color {
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

    public var defaultTitle: String {
        rawValue.capitalized
    }
}

// MARK: - Admonition Card View (Core, cross-platform)

public struct AdmonitionCardViewCore: View {
    public let kind: AdmonitionKind
    public let title: String
    public let content: String
    @Environment(\.appTextScale) private var appTextScale

    public init(kind: AdmonitionKind, title: String, content: String) {
        self.kind = kind
        self.title = title
        self.content = content
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.color)
                .font(.system(size: 14 * appTextScale))
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? kind.defaultTitle : title)
                    .font(.system(size: 12 * appTextScale, weight: .semibold))
                    .fontWeight(.semibold)
                    .foregroundStyle(kind.color)

                if !content.isEmpty {
                    Markdown(content)
                        .markdownTheme(.odysseyCore(scale: appTextScale))
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
    }
}

// MARK: - Theme Extension

extension Theme {
    @MainActor
    public static func odysseyCore(scale: CGFloat) -> Theme {
        Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(14 * scale)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(.secondary)
#if os(macOS)
            BackgroundColor(Color(nsColor: .textBackgroundColor).opacity(0.5))
#else
            BackgroundColor(Color(uiColor: .secondarySystemBackground).opacity(0.5))
#endif
        }
        .link {
            ForegroundColor(.accentColor)
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(24 * scale)
                }
                .markdownMargin(top: 16, bottom: 8)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(20 * scale)
                }
                .markdownMargin(top: 14, bottom: 6)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(17 * scale)
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
}
