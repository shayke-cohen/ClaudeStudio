import SwiftUI
import MarkdownUI

struct MarkdownContent: View {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(.claudPeer)
            .textSelection(.enabled)
            .accessibilityIdentifier("markdownContent")
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
