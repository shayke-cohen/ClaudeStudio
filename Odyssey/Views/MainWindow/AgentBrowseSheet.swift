import SwiftUI
import SwiftData

enum AgentBrowseTab: String, CaseIterable, Identifiable {
    case agents = "Agents"
    case groups = "Groups"
    var id: String { rawValue }
}

struct AgentBrowseSheet: View {
    let initialTab: AgentBrowseTab
    let projectId: UUID?
    let projectDirectory: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState

    @Query(sort: \Agent.name) private var allAgents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var allGroups: [AgentGroup]
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    @State private var selectedTab: AgentBrowseTab
    @State private var searchText = ""

    init(initialTab: AgentBrowseTab, projectId: UUID?, projectDirectory: String) {
        self.initialTab = initialTab
        self.projectId = projectId
        self.projectDirectory = projectDirectory
        _selectedTab = State(initialValue: initialTab)
    }

    private var enabledAgents: [Agent] { allAgents.filter(\.isEnabled) }
    private var enabledGroups: [AgentGroup] { allGroups.filter(\.isEnabled) }

    private var filteredAgents: [Agent] {
        guard !searchText.isEmpty else { return enabledAgents }
        return enabledAgents.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredGroups: [AgentGroup] {
        guard !searchText.isEmpty else { return enabledGroups }
        return enabledGroups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            searchBar
            Divider()
            content
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Browse")
                .font(.headline)
            Spacer()
            Picker("", selection: $selectedTab) {
                ForEach(AgentBrowseTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.escape)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField(
                selectedTab == .agents ? "Search agents…" : "Search groups…",
                text: $searchText
            )
            .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            if selectedTab == .agents {
                agentGrid
            } else {
                groupList
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var agentGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(filteredAgents) { agent in
                AgentBrowseCard(agent: agent, allSkills: allSkills, allMCPs: allMCPs) {
                    startChat(agent: agent)
                }
            }
        }
        .padding(20)
    }

    private var groupList: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredGroups) { group in
                GroupBrowseCard(group: group, allAgents: allAgents) {
                    startGroupChat(group: group)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Actions

    private func startChat(agent: Agent) {
        let conversation = Conversation(topic: nil, projectId: projectId, threadKind: .direct)
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        let session = Session(agent: agent, mission: nil, workingDirectory: projectDirectory)
        session.conversations = [conversation]
        conversation.sessions.append(session)

        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: agent.name
        )
        agentParticipant.conversation = conversation
        conversation.participants.append(agentParticipant)

        modelContext.insert(userParticipant)
        modelContext.insert(agentParticipant)
        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
        dismiss()
    }

    private func startGroupChat(group: AgentGroup) {
        guard let convId = appState.startGroupChat(
            group: group,
            projectDirectory: projectDirectory,
            projectId: projectId,
            modelContext: modelContext,
            missionOverride: nil
        ) else { return }
        windowState.selectedConversationId = convId
        dismiss()
    }
}

// MARK: - Agent Card

private struct AgentBrowseCard: View {
    let agent: Agent
    let allSkills: [Skill]
    let allMCPs: [MCPServer]
    let onStart: () -> Void

    private var skills: [Skill] {
        agent.skillIds.compactMap { id in allSkills.first { $0.id == id } }
    }

    private var mcps: [MCPServer] {
        agent.extraMCPServerIds.compactMap { id in allMCPs.first { $0.id == id } }
    }

    private var resolvedModel: String {
        AgentDefaults.resolveEffectiveModel(agentSelection: agent.model, provider: agent.provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: agent.icon)
                    .font(.title2)
                    .foregroundStyle(Color.fromAgentColor(agent.color))
                    .frame(width: 44, height: 44)
                    .background(Color.fromAgentColor(agent.color).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.headline)
                        .lineLimit(1)
                    if !resolvedModel.isEmpty {
                        Text(resolvedModel)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }

            // Description
            if !agent.agentDescription.isEmpty {
                Text(agent.agentDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No description")
                    .font(.callout)
                    .foregroundStyle(.quaternary)
                    .italic()
            }

            // Skills
            if !skills.isEmpty {
                chipRow(
                    icon: "brain",
                    color: .purple,
                    items: skills.map(\.name),
                    maxVisible: 4
                )
            }

            // MCPs
            if !mcps.isEmpty {
                chipRow(
                    icon: "puzzlepiece",
                    color: .indigo,
                    items: mcps.map(\.name),
                    maxVisible: 3
                )
            }

            Spacer(minLength: 4)

            Button("Start Chat") { onStart() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }

    private func chipRow(icon: String, color: Color, items: [String], maxVisible: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color.opacity(0.8))
            FlowChips(items: items, maxVisible: maxVisible, color: color)
        }
    }
}

// MARK: - Group Card

private struct GroupBrowseCard: View {
    let group: AgentGroup
    let allAgents: [Agent]
    let onStart: () -> Void

    private var memberAgents: [(agent: Agent, role: GroupRole)] {
        group.agentIds.compactMap { id -> (Agent, GroupRole)? in
            guard let agent = allAgents.first(where: { $0.id == id }) else { return nil }
            return (agent, group.roleFor(agentId: id))
        }
    }

    private var workflowSteps: [WorkflowStep] { group.workflow ?? [] }

    private var coordinatorAgent: Agent? {
        guard let cid = group.coordinatorAgentId else { return nil }
        return allAgents.first { $0.id == cid }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: icon + name + badges + Start Chat
            HStack(spacing: 10) {
                Text(group.icon)
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(Color.fromAgentColor(group.color).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text("\(group.agentIds.count) agent\(group.agentIds.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if group.autonomousCapable {
                            capabilityBadge("Autonomous", color: .orange)
                        }
                        if group.autoReplyEnabled {
                            capabilityBadge("Auto-reply", color: .green)
                        }
                    }
                }
                Spacer()
                Button("Start Chat") { onStart() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }

            Divider()

            // Two-column body: left = purpose, right = structure
            HStack(alignment: .top, spacing: 0) {
                // Left pane — description + instruction
                VStack(alignment: .leading, spacing: 8) {
                    if !group.groupDescription.isEmpty {
                        Text(group.groupDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No description")
                            .font(.callout)
                            .foregroundStyle(.quaternary)
                            .italic()
                    }
                    if !group.groupInstruction.isEmpty {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                            Text(group.groupInstruction)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(.secondary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                // Vertical divider
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .padding(.horizontal, 14)

                // Right pane — members + workflow
                VStack(alignment: .leading, spacing: 10) {
                    if !memberAgents.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("MEMBERS")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(memberAgents.prefix(6), id: \.agent.id) { member in
                                    memberRow(member.agent, role: member.role)
                                }
                            }
                            if memberAgents.count > 6 {
                                Text("+\(memberAgents.count - 6) more")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if !workflowSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Text("WORKFLOW")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                Text("· \(workflowSteps.count) steps")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(workflowSteps.prefix(5).enumerated()), id: \.offset) { idx, step in
                                    workflowStepRow(index: idx + 1, step: step)
                                }
                            }
                            if workflowSteps.count > 5 {
                                Text("+\(workflowSteps.count - 5) more")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 22)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }

    private func memberRow(_ agent: Agent, role: GroupRole) -> some View {
        HStack(spacing: 6) {
            Image(systemName: agent.icon)
                .font(.system(size: 9))
                .foregroundStyle(Color.fromAgentColor(agent.color))
                .frame(width: 20, height: 20)
                .background(Color.fromAgentColor(agent.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(agent.name)
                .font(.caption)
                .lineLimit(1)
            if !role.emoji.isEmpty {
                Text(role.emoji)
                    .font(.system(size: 10))
            }
            Spacer(minLength: 0)
        }
    }

    private func workflowStepRow(index: Int, step: WorkflowStep) -> some View {
        let agentName = allAgents.first(where: { $0.id == step.agentId })?.name ?? "Unknown"
        let label = step.stepLabel ?? step.instruction.prefix(40).description
        return HStack(alignment: .top, spacing: 6) {
            Text("\(index)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Color.secondary.opacity(0.5))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
                Text(agentName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if step.artifactGate != nil {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func capabilityBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: - Flow Chips

private struct FlowChips: View {
    let items: [String]
    let maxVisible: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.prefix(maxVisible), id: \.self) { item in
                Text(item)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.1))
                    .clipShape(Capsule())
            }
            if items.count > maxVisible {
                Text("+\(items.count - maxVisible)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
