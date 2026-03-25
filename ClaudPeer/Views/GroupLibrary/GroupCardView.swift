import SwiftUI
import SwiftData

struct GroupCardView: View {
    let group: AgentGroup
    let agents: [Agent]
    let onStart: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.icon)
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .background(Color.fromAgentColor(group.color).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityIdentifier("groupCard.name")
                    Text(originLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("groupCard.originLabel")
                }
                Spacer()
            }

            if !group.groupDescription.isEmpty {
                Text(group.groupDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("groupCard.description")
            }

            Divider()

            Text(agentNamesText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("groupCard.agentNames")

            HStack {
                Button("Start Chat", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("groupCard.startButton")

                Button("Edit", action: onEdit)
                    .controlSize(.small)
                    .accessibilityIdentifier("groupCard.editButton")
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
        .opacity(group.isEnabled ? 1.0 : 0.5)
    }

    private var agentNamesText: String {
        let agentById = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let names = group.agentIds.compactMap { agentById[$0]?.name }
        return names.isEmpty ? "No agents" : names.joined(separator: " \u{00B7} ")
    }

    private var originLabel: String {
        switch group.origin {
        case .local: return "Local"
        case .peer: return "Shared"
        case .imported: return "Imported"
        case .builtin: return "Built-in"
        }
    }
}
