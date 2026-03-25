import SwiftUI

/// Renders bash/shell tool results in a terminal-styled block with dark background and monospace font.
struct TerminalOutputView: View {
    let command: String
    let output: String
    @State private var isExpanded = true
    @State private var copiedCommand = false
    @State private var copiedOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().opacity(0.2)
                commandLine
                if !output.isEmpty {
                    Divider().opacity(0.1)
                    outputContent
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .xrayId("terminalOutput.container")
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(.green)
                    .font(.caption)

                Text("Terminal")
                    .font(.caption)
                    .fontWeight(.medium)

                if !output.isEmpty {
                    Text("\(lineCount) lines")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .init(white: 0.12, alpha: 1)))
        .xrayId("terminalOutput.header")
    }

    // MARK: - Command Line

    @ViewBuilder
    private var commandLine: some View {
        HStack(spacing: 4) {
            Text("$")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.green.opacity(0.8))

            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .lineLimit(3)

            Spacer(minLength: 4)

            Button {
                copyToClipboard(command)
                withAnimation { copiedCommand = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copiedCommand = false }
                }
            } label: {
                Image(systemName: copiedCommand ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(copiedCommand ? .green : .gray)
            }
            .buttonStyle(.borderless)
            .help("Copy command")
            .xrayId("terminalOutput.copyCommand")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .init(white: 0.1, alpha: 1)))
    }

    // MARK: - Output Content

    @ViewBuilder
    private var outputContent: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(trimmedOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .init(white: 0.85, alpha: 1)))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .frame(maxHeight: 300)
            .background(Color(nsColor: .init(white: 0.08, alpha: 1)))

            Button {
                copyToClipboard(output)
                withAnimation { copiedOutput = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copiedOutput = false }
                }
            } label: {
                Image(systemName: copiedOutput ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(copiedOutput ? .green : .gray)
                    .padding(4)
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.borderless)
            .padding(6)
            .help("Copy output")
            .xrayId("terminalOutput.copyOutput")
        }
    }

    // MARK: - Helpers

    private var trimmedOutput: String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var lineCount: Int {
        trimmedOutput.components(separatedBy: "\n").count
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Factory

extension TerminalOutputView {
    /// Try to create a TerminalOutputView from a tool call + result pair.
    static func fromBashToolCall(input: String?, output: String?) -> TerminalOutputView? {
        guard let input = input else { return nil }

        // Try to parse command from JSON input
        var command = input
        if let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cmd = json["command"] as? String {
            command = cmd
        }

        return TerminalOutputView(
            command: command,
            output: output ?? ""
        )
    }
}
