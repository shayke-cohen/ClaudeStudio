import SwiftUI
import SwiftData

struct GroupPopoverView: View {
    let group: AgentGroup
    let agents: [Agent]
    let conversations: [Conversation]
    let onStartChat: () -> Void
    let onStartAutonomous: (() -> Void)?
    let onEdit: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            teamSection
            Divider()
            if let steps = group.workflow, !steps.isEmpty {
                workflowSection(steps)
                Divider()
            }
            if !conversations.isEmpty {
                recentSection
                Divider()
            }
            actionsSection
        }
        .frame(width: 320)
        .xrayId("groupPopover")
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(group.icon)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.fromAgentColor(group.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)
                    .xrayId("groupPopover.name")

                if !group.groupDescription.isEmpty {
                    Text(group.groupDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    if group.autoReplyEnabled {
                        miniPill("Auto-Reply", color: .green)
                    }
                    if group.autonomousCapable {
                        miniPill("Autonomous", color: .orange)
                    }
                    if group.workflow != nil {
                        miniPill("Workflow", color: .teal)
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: - Team

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TEAM")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)

            FlowLayout(spacing: 4) {
                ForEach(resolvedAgents) { agent in
                    HStack(spacing: 4) {
                        Image(systemName: agent.icon)
                            .font(.caption2)
                            .foregroundStyle(Color.fromAgentColor(agent.color))
                        Text(agent.name)
                            .font(.caption)
                        let role = group.roleFor(agentId: agent.id)
                        if role != .participant {
                            Text(role.displayName)
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(roleColor(role).opacity(0.15))
                                .foregroundStyle(roleColor(role))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .padding(12)
        .xrayId("groupPopover.team")
    }

    // MARK: - Workflow

    private func workflowSection(_ steps: [WorkflowStep]) -> some View {
        let agentById = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        return VStack(alignment: .leading, spacing: 6) {
            Text("WORKFLOW")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 3) {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 16, height: 16)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Circle())
                        Text(step.stepLabel ?? agentById[step.agentId]?.name ?? "Step")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    if index < steps.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.quaternary)
                    }
                }
            }
        }
        .padding(12)
        .xrayId("groupPopover.workflow")
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RECENT")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)

            ForEach(conversations.prefix(3)) { conv in
                HStack(spacing: 6) {
                    Circle()
                        .fill(conv.sessions.contains(where: { $0.status == .active }) ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(conv.topic ?? "Untitled")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(conv.startedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .xrayId("groupPopover.recent")
    }

    // MARK: - Actions

    private var actionsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            popoverButton("Start Chat", icon: "play.fill", primary: true, action: onStartChat)
                .xrayId("groupPopover.startChatButton")
            if let onAuto = onStartAutonomous {
                popoverButton("Autonomous", icon: "bolt.fill", action: onAuto)
                    .xrayId("groupPopover.autonomousButton")
            }
            popoverButton("Edit", icon: "pencil", action: onEdit)
                .xrayId("groupPopover.editButton")
            popoverButton("Duplicate", icon: "doc.on.doc", action: onDuplicate)
                .xrayId("groupPopover.duplicateButton")
        }
        .padding(12)
    }

    // MARK: - Shared

    private var resolvedAgents: [Agent] {
        let byId = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        return group.agentIds.compactMap { byId[$0] }
    }

    @ViewBuilder
    private func miniPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9))
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func popoverButton(_ label: String, icon: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(primary ? Color.accentColor : Color.primary.opacity(0.06))
            .foregroundStyle(primary ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func roleColor(_ role: GroupRole) -> Color {
        switch role {
        case .coordinator: .orange
        case .scribe: .purple
        case .observer: .gray
        case .participant: .secondary
        }
    }
}
