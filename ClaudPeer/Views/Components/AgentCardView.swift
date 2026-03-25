import SwiftUI

struct AgentCardView: View {
    let agent: Agent
    let onStart: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: agent.icon)
                    .font(.title2)
                    .foregroundStyle(colorFromString(agent.color))
                    .frame(width: 36, height: 36)
                    .background(colorFromString(agent.color).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.headline)
                        .lineLimit(1)
                        .xrayId("agentCard.name")
                    Text(originLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .xrayId("agentCard.originLabel")
                }
                Spacer()
            }

            if !agent.agentDescription.isEmpty {
                Text(agent.agentDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .xrayId("agentCard.description")
            }

            Divider()

            HStack(spacing: 12) {
                Label("\(agent.skillIds.count)", systemImage: "book.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label("\(agent.extraMCPServerIds.count)", systemImage: "server.rack")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label(agent.model, systemImage: "cpu")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .xrayId("agentCard.startButton")

                Button("Edit", action: onEdit)
                    .controlSize(.small)
                    .xrayId("agentCard.editButton")
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
        .opacity(agent.isEnabled ? 1.0 : 0.5)
    }

    private var originLabel: String {
        switch agent.origin {
        case .local: return "Local"
        case .peer: return "Shared"
        case .imported: return "Imported"
        case .builtin: return "Built-in"
        }
    }

    private func colorFromString(_ color: String) -> Color {
        Color.fromAgentColor(color)
    }
}
