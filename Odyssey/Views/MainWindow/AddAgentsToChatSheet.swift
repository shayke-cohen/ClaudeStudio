import SwiftUI
import SwiftData

/// Add one or more agents to an existing conversation (new `Session` + participant each).
struct AddAgentsToChatSheet: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sharedRoomService: SharedRoomService
    @Environment(WindowState.self) private var windowState: WindowState
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query private var allConversations: [Conversation]

    @State private var selectedIds: Set<UUID> = []
    @State private var selectedGroupIds: Set<UUID> = []

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    private var existingAgentIds: Set<UUID> {
        guard let convo = conversation else { return [] }
        return Set(
            convo.sessions.compactMap(\.agent?.id)
        )
    }

    private var addableAgents: [Agent] {
        agents.filter { !existingAgentIds.contains($0.id) }
    }

    private var addableGroups: [AgentGroup] {
        groups.filter { group in
            group.isEnabled && group.agentIds.contains { !existingAgentIds.contains($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add agents or groups")
                .font(.headline)
                .xrayId("addAgents.title")

            Text(conversation?.isSharedRoom == true
                 ? "Selected agents or group members join this shared room and publish from your local workspace."
                 : "Selected agents or group members join this conversation and receive the next messages.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !addableGroups.isEmpty {
                        Text("Groups")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)

                        ForEach(addableGroups) { group in
                            Toggle(isOn: Binding(
                                get: { selectedGroupIds.contains(group.id) },
                                set: { on in
                                    if on { selectedGroupIds.insert(group.id) } else { selectedGroupIds.remove(group.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(group.icon)
                                        Text(group.name)
                                    }
                                    Text(group.agentIds.compactMap { id in
                                        agents.first(where: { $0.id == id })?.name
                                    }.joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .xrayId("addAgents.groupToggle.\(group.id.uuidString)")
                        }
                    }

                    if !addableGroups.isEmpty && !addableAgents.isEmpty {
                        Divider().padding(.vertical, 4)
                    }

                    if !addableAgents.isEmpty {
                        Text("Agents")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)
                    }

                    ForEach(addableAgents) { agent in
                        Toggle(isOn: Binding(
                            get: { selectedIds.contains(agent.id) },
                            set: { on in
                                if on { selectedIds.insert(agent.id) } else { selectedIds.remove(agent.id) }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: agent.icon)
                                    .foregroundStyle(Color.fromAgentColor(agent.color))
                                Text(agent.name)
                            }
                        }
                        .xrayId("addAgents.toggle.\(agent.id.uuidString)")
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 280)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .xrayId("addAgents.cancelButton")
                Spacer()
                Button("Add") { addSelected() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIds.isEmpty && selectedGroupIds.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    .xrayId("addAgents.confirmButton")
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func addSelected() {
        guard let convo = conversation else {
            dismiss()
            return
        }
        let primaryWd = (convo.primarySession?.workingDirectory ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mission = convo.primarySession?.mission
        let mode = convo.primarySession?.mode ?? .interactive

        let groupAgentIds = Set(
            groups
                .filter { selectedGroupIds.contains($0.id) }
                .flatMap(\.agentIds)
        )
        let agentIdsToAdd = selectedIds.union(groupAgentIds).subtracting(existingAgentIds)

        for agent in agents where agentIdsToAdd.contains(agent.id) {
            let wd = !primaryWd.isEmpty ? primaryWd : ""
            let session = Session(
                agent: agent,
                mission: mission,
                mode: mode,
                workingDirectory: wd
            )
            session.conversations = [convo]
            convo.sessions.append(session)

            let agentParticipant = Participant(
                type: .agentSession(sessionId: session.id),
                displayName: agent.name
            )
            agentParticipant.conversation = convo
            convo.participants.append(agentParticipant)

            if let bundleJSON = agent.identityBundleJSON,
               let bundleData = bundleJSON.data(using: .utf8),
               let bundle = try? JSONDecoder().decode(AgentIdentityBundle.self, from: bundleData) {
                agentParticipant.isVerified = IdentityManager.shared.verifyAgentBundle(bundle)
                agentParticipant.ownerPublicKeyData = bundle.ownerPublicKeyData
                agentParticipant.agentIdentityBundleJSON = bundleJSON
                agentParticipant.ownerDisplayName = IdentityManager.shared.ownerDisplayName(for: bundle)
            }

            modelContext.insert(session)
        }

        if convo.sessions.count > 1 {
            convo.threadKind = .group
        }

        // Ensure all new sessions have a working directory.
        // Resident agents run in their own home folder; everyone else in the project root.
        for session in convo.sessions where session.workingDirectory.isEmpty {
            if let dir = session.agent?.defaultWorkingDirectory, !dir.isEmpty {
                session.workingDirectory = dir
            } else {
                session.workingDirectory = windowState.projectDirectory
            }
        }
        try? modelContext.save()
        if convo.isSharedRoom {
            Task {
                await sharedRoomService.publishLocalParticipants(for: convo)
            }
        }
        dismiss()
    }
}
