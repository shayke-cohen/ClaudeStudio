import SwiftUI

struct AgentCardView: View {
    let agent: Agent
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
                    Text(originLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !agent.agentDescription.isEmpty {
                Text(agent.agentDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Divider()

            HStack(spacing: 12) {
                Label("\(agent.skillIds.count)", systemImage: "book.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label("\(agent.mcpServerIds.count)", systemImage: "server.rack")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label(agent.model, systemImage: "cpu")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Start") {
                    // TODO: Start session with this agent
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Edit", action: onEdit)
                    .controlSize(.small)
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
    }

    private var originLabel: String {
        switch agent.origin {
        case .local: return "Local"
        case .peer: return "Shared"
        case .imported: return "Imported"
        }
    }

    private func colorFromString(_ color: String) -> Color {
        switch color {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        case "yellow": return .yellow
        case "pink": return .pink
        case "teal": return .teal
        default: return .accentColor
        }
    }
}
