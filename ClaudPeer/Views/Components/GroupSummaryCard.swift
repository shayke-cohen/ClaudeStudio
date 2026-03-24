import SwiftUI

struct GroupSummaryCard: View {
    let summary: GroupSummaryBuilder.GroupSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(.blue)
                Text("Group Activity Summary")
                    .font(.headline)
                Spacer()
                Text(formatDuration(summary.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label("\(summary.totalMessages) messages", systemImage: "bubble.left.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(summary.totalToolCalls) tool calls", systemImage: "wrench.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(summary.contributions) { contribution in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: contribution.agentIcon)
                            .foregroundStyle(Color.fromAgentColor(contribution.agentColor))
                            .frame(width: 16)
                        Text(contribution.agentName)
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(contribution.messageCount) msgs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if contribution.toolCallCount > 0 {
                            Text("\(contribution.toolCallCount) tools")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(contribution.keyActions, id: \.self) { action in
                        Text(action)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .padding(.leading, 20)
                    }
                }
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .accessibilityIdentifier("groupSummaryCard")
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 1 { return "\(Int(seconds))s" }
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}
