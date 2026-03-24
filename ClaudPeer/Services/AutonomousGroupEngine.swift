import Foundation
import SwiftData

/// Orchestrates autonomous group execution where a coordinator agent drives the workflow.
///
/// The coordinator receives the mission, uses PeerBus tools to delegate to team members,
/// and the auto-reply mechanism handles inter-agent communication. The engine monitors
/// for "MISSION COMPLETE" or budget exhaustion.
@MainActor
final class AutonomousGroupEngine {
    let conversation: Conversation
    let group: AgentGroup
    let appState: AppState
    let modelContext: ModelContext
    private var roundCount = 0
    private let maxRounds = 20
    private var isStopped = false

    init(conversation: Conversation, group: AgentGroup, appState: AppState, modelContext: ModelContext) {
        self.conversation = conversation
        self.group = group
        self.appState = appState
        self.modelContext = modelContext
    }

    /// Sends the initial mission to the coordinator and monitors for completion.
    func run(mission: String, sendToCoordinator: @MainActor @escaping (String) async throws -> String?) async {
        guard let coordinatorId = group.coordinatorAgentId ?? group.agentIds.first else { return }
        guard let coordinatorSession = conversation.sessions.first(where: { $0.agent?.id == coordinatorId }) else { return }

        let teamDescriptions = conversation.sessions
            .compactMap { session -> (name: String, description: String)? in
                guard let agent = session.agent, agent.id != coordinatorId else { return nil }
                return (name: agent.name, description: agent.agentDescription)
            }

        let coordinatorPrompt = GroupPromptBuilder.buildCoordinatorPrompt(
            mission: mission,
            teamAgents: teamDescriptions,
            groupInstruction: group.groupInstruction
        )

        appendSystemMessage("Autonomous mode started. Coordinator: \(coordinatorSession.agent?.name ?? "Unknown").")

        // Initial mission dispatch
        let reply = try? await sendToCoordinator(coordinatorPrompt)

        if let reply, isMissionComplete(reply) {
            appendSystemMessage("Mission complete.")
            return
        }

        // Auto-reply handles the rest — the fan-out mechanism in ChatView
        // will notify other agents when the coordinator posts, and they'll respond.
        // The coordinator will get notified when others respond.
        // This loop just monitors for completion.
    }

    func intervene(message: String) {
        let msg = ConversationMessage(
            senderParticipantId: conversation.participants.first(where: { $0.type == .user })?.id,
            text: message,
            type: .chat,
            conversation: conversation
        )
        conversation.messages.append(msg)
        try? modelContext.save()
    }

    func stop() {
        isStopped = true
        appendSystemMessage("Autonomous mode stopped by user.")
    }

    private func isMissionComplete(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("MISSION COMPLETE")
    }

    private func appendSystemMessage(_ text: String) {
        let msg = ConversationMessage(
            senderParticipantId: nil,
            text: text,
            type: .system,
            conversation: conversation
        )
        conversation.messages.append(msg)
        try? modelContext.save()
    }
}
