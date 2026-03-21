import SwiftUI

struct ToolCallView: View {
    let message: ConversationMessage
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: message.type == .toolCall ? "wrench.fill" : "checkmark.circle.fill")
                        .foregroundStyle(message.type == .toolCall ? .blue : .green)
                        .font(.caption)

                    Text(message.toolName ?? "Tool")
                        .font(.caption)
                        .fontWeight(.medium)
                        .accessibilityIdentifier("toolCall.title.\(message.id.uuidString)")

                    if message.type == .toolResult {
                        Text("completed")
                            .font(.caption2)
                            .foregroundStyle(.green)
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
            .help(isExpanded ? "Collapse tool details" : "Expand tool details")
            .accessibilityIdentifier("toolCall.toggleButton.\(message.id.uuidString)")
            .accessibilityLabel("\(message.toolName ?? "Tool") - \(isExpanded ? "collapse" : "expand")")

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    if let input = message.toolInput, !input.isEmpty {
                        Text("Input:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(input)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(10)
                    }
                    if let output = message.toolOutput, !output.isEmpty {
                        Text("Output:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(10)
                    }
                    if message.text.isEmpty == false {
                        Text(message.text)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .background(.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }
}
