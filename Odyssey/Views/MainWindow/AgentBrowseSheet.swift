import SwiftUI
import SwiftData

enum AgentBrowseTab: String, CaseIterable {
    case agents = "Agents"
    case groups = "Groups"
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

    @State private var selectedTab: AgentBrowseTab = .agents
    @State private var searchText = ""

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
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { selectedTab = initialTab }
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
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
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
                groupGrid
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
                AgentBrowseCard(agent: agent) {
                    startChat(agent: agent)
                }
            }
        }
        .padding(20)
    }

    private var groupGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
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
        let conversation = Conversation(
            topic: nil,
            projectId: projectId,
            threadKind: .direct
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        let session = Session(
            agent: agent,
            mission: nil,
            workingDirectory: projectDirectory
        )
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
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    let resolved = AgentDefaults.resolveEffectiveModel(
                        agentSelection: agent.model,
                        provider: agent.provider
                    )
                    if !resolved.isEmpty {
                        Text(resolved)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.bottom, 10)

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

            Spacer(minLength: 12)

            Button("Start Chat") { onStart() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }
}

// MARK: - Group Card

private struct GroupBrowseCard: View {
    let group: AgentGroup
    let allAgents: [Agent]
    let onStart: () -> Void

    private var memberAgents: [Agent] {
        group.agentIds.prefix(4).compactMap { id in
            allAgents.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(group.icon)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color.fromAgentColor(group.color).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(group.agentIds.count) agent\(group.agentIds.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.bottom, 10)

            if !group.groupDescription.isEmpty {
                Text(group.groupDescription)
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

            Spacer(minLength: 12)

            HStack {
                HStack(spacing: -6) {
                    ForEach(memberAgents) { agent in
                        Image(systemName: agent.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.fromAgentColor(agent.color))
                            .frame(width: 20, height: 20)
                            .background(Color.fromAgentColor(agent.color).opacity(0.18))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.background, lineWidth: 1.5))
                    }
                }
                Spacer()
                Button("Start Chat") { onStart() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }
}
