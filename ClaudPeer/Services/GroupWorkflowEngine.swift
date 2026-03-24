import Foundation
import SwiftData

/// Orchestrates step-by-step workflow execution for group conversations.
///
/// When a group has a workflow defined, only the agent for the current step is activated.
/// After each step completes, the engine optionally auto-advances to the next step.
@MainActor
final class GroupWorkflowEngine {
    let conversation: Conversation
    let group: AgentGroup
    let workflow: [WorkflowStep]
    let appState: AppState
    let modelContext: ModelContext

    private var previousStepOutput: String?

    init(conversation: Conversation, group: AgentGroup, workflow: [WorkflowStep], appState: AppState, modelContext: ModelContext) {
        self.conversation = conversation
        self.group = group
        self.workflow = workflow
        self.appState = appState
        self.modelContext = modelContext
    }

    func execute(userMessage: String, manager: SidecarManager, sendToSession: @MainActor @escaping (Session, String, AgentConfig?) async throws -> String?) async {
        let startStep = conversation.workflowCurrentStep ?? 0
        previousStepOutput = nil

        for stepIndex in startStep..<workflow.count {
            let step = workflow[stepIndex]
            conversation.workflowCurrentStep = stepIndex
            try? modelContext.save()

            guard let session = findSession(for: step.agentId) else {
                appendSystemMessage("Workflow step \(stepIndex + 1): agent not found, skipping.")
                markStepCompleted(stepIndex)
                continue
            }

            let role = group.roleFor(agentId: step.agentId)
            let prompt = GroupPromptBuilder.buildWorkflowStepPrompt(
                step: step,
                stepIndex: stepIndex,
                totalSteps: workflow.count,
                userMessage: userMessage,
                previousStepOutput: previousStepOutput,
                groupInstruction: group.groupInstruction,
                role: role
            )

            let reply = try? await sendToSession(session, prompt, nil)
            previousStepOutput = reply
            markStepCompleted(stepIndex)

            if !step.autoAdvance {
                appendSystemMessage("Step \(stepIndex + 1)/\(workflow.count) complete (\(step.stepLabel ?? "done")). Send a message to continue.")
                conversation.workflowCurrentStep = stepIndex + 1
                try? modelContext.save()
                return
            }

            if let condition = step.condition, !condition.isEmpty {
                let output = (reply ?? "").lowercased()
                let conditionLower = condition.lowercased()
                if !output.contains(conditionLower) {
                    appendSystemMessage("Step \(stepIndex + 1) condition \"\(condition)\" not met. Workflow paused.")
                    conversation.workflowCurrentStep = stepIndex + 1
                    try? modelContext.save()
                    return
                }
            }
        }

        // All steps complete
        conversation.workflowCurrentStep = nil
        appendSystemMessage("Workflow complete (\(workflow.count) steps).")
        try? modelContext.save()
    }

    func skipToStep(_ index: Int) {
        guard index >= 0 && index < workflow.count else { return }
        conversation.workflowCurrentStep = index
        try? modelContext.save()
    }

    // MARK: - Helpers

    private func findSession(for agentId: UUID) -> Session? {
        conversation.sessions.first { $0.agent?.id == agentId }
    }

    private func markStepCompleted(_ index: Int) {
        var completed = conversation.workflowCompletedSteps ?? []
        if !completed.contains(index) {
            completed.append(index)
        }
        conversation.workflowCompletedSteps = completed
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
