import SwiftUI
import SwiftData

struct AgentPickerPopover: View {
    let projectId: UUID?
    let projectDirectory: String
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState: WindowState

    @Query(sort: \Agent.name) private var allAgents: [Agent]
    @Query(sort: \Session.lastActiveAt, order: .reverse) private var recentSessions: [Session]

    @State private var searchText = ""
    @State private var missionText = ""
    @State private var showMission = false
    @FocusState private var searchFocused: Bool
    @FocusState private var missionFocused: Bool

    private var enabledAgents: [Agent] {
        allAgents.filter { $0.isEnabled }
    }

    private var filteredAgents: [Agent] {
        guard !searchText.isEmpty else { return enabledAgents }
        return enabledAgents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var recentAgents: [Agent] {
        var seen = Set<UUID>()
        var result: [Agent] = []
        for session in recentSessions {
            guard let agent = session.agent,
                  agent.isEnabled,
                  !seen.contains(agent.id) else { continue }
            seen.insert(agent.id)
            result.append(agent)
            if result.count == 3 { break }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if showMission { missionSection }
            noAgentRow
            Divider()
            if !recentAgents.isEmpty && searchText.isEmpty { recentSection }
            agentList
            Divider()
            footer
        }
        .frame(width: 260)
        .background(.background)
        .onAppear { searchFocused = true }
    }
}

// MARK: - Subviews

extension AgentPickerPopover {
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            TextField("Search agents…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.secondary)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MISSION")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.purple)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            TextEditor(text: $missionText)
                .font(.system(size: 12))
                .focused($missionFocused)
                .frame(height: 56)
                .padding(.horizontal, 8)
                .scrollContentBackground(.hidden)
                .background(Color.purple.opacity(0.08))
            Text("Select an agent below to start  ·  esc to cancel")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .background(Color.purple.opacity(0.06))
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var noAgentRow: some View {
        Button { openThread(agent: nil) } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .foregroundStyle(.quaternary)
                    Text("∅")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
                .frame(width: 20, height: 20)
                Text("No specialized agent")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↵")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RECENT")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(recentAgents) { agent in
                        Button { openThread(agent: agent) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: agent.icon)
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color.fromAgentColor(agent.color))
                                Text(agent.name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.background.secondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var agentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredAgents) { agent in
                    Button { openThread(agent: agent) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: agent.icon)
                                .font(.system(size: 10))
                                .frame(width: 20, height: 20)
                                .background(Color.fromAgentColor(agent.color).opacity(0.15))
                                .foregroundStyle(Color.fromAgentColor(agent.color))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(agent.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                let resolvedModel = AgentDefaults.resolveEffectiveModel(
                                    agentSelection: agent.model,
                                    provider: agent.provider
                                )
                                if !resolvedModel.isEmpty {
                                    Text(resolvedModel)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.quaternary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 200)
    }

    private var footer: some View {
        HStack {
            Text("Click to start")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            Spacer()
            Button("") { toggleMission() }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
            Text(showMission ? "⌘↵ hide mission" : "⌘↵ add mission")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.background.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Actions

extension AgentPickerPopover {
    private func toggleMission() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showMission.toggle()
        }
        if showMission { missionFocused = true }
    }

    private func openThread(agent: Agent?) {
        let mission = missionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: ThreadKind = agent != nil ? .direct : .freeform

        let conversation = Conversation(
            topic: nil,
            projectId: projectId,
            threadKind: kind
        )

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        let agentHome = agent?.defaultWorkingDirectory.flatMap { $0.isEmpty ? nil : $0 }
        let effectiveWD = agentHome.map { NSString(string: $0).expandingTildeInPath as String }
            ?? (projectDirectory.isEmpty ? "" : projectDirectory)
        let session = Session(
            agent: agent,
            mission: mission.isEmpty ? nil : mission,
            workingDirectory: effectiveWD
        )
        session.conversations = [conversation]
        conversation.sessions.append(session)

        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: agent?.name ?? AgentDefaults.displayName(forProvider: session.provider)
        )
        agentParticipant.conversation = conversation
        conversation.participants.append(agentParticipant)

        modelContext.insert(userParticipant)
        modelContext.insert(agentParticipant)
        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
        isPresented = false
    }
}
