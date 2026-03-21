import SwiftUI
import MarkdownUI

struct CodeBlockView: View {
    let configuration: CodeBlockConfiguration
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.3)
            codeContent
        }
        .background(Color(.textBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            if let language = configuration.language, !language.isEmpty {
                Text(language)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textCase(.lowercase)
                    .accessibilityIdentifier("codeBlock.languageLabel")
            }

            Spacer()

            Button {
                copyToClipboard()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.caption2)
                }
                .foregroundStyle(isCopied ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Copy code to clipboard")
            .accessibilityIdentifier("codeBlock.copyButton")
            .accessibilityLabel("Copy code")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var codeContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(configuration.content.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
        }
        .accessibilityIdentifier("codeBlock.codeScrollView")
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            configuration.content.trimmingCharacters(in: .whitespacesAndNewlines),
            forType: .string
        )
        withAnimation {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}
