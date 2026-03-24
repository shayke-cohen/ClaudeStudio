import SwiftUI
import SwiftData

struct GroupSidebarRowView: View {
    let group: AgentGroup
    let agentCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(group.icon)
                .font(.body)
                .frame(width: 22, height: 22)
                .background(Color.fromAgentColor(group.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text(group.name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text("\(agentCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("sidebar.groupRow.\(group.id.uuidString)")
    }
}
