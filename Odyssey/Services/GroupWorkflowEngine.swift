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

            let artifactGate = artifactGate(after: stepIndex, session: session)

            if artifactGate != nil || !step.autoAdvance {
                let pauseMessage: String
                if let artifactGate {
                    let reviewTarget = artifactReviewTarget(for: artifactGate.profile)
                    if artifactGate.approvalRequired {
                        pauseMessage = "Step \(stepIndex + 1)/\(workflow.count) complete (\(step.stepLabel ?? "done")). Review the \(reviewTarget), approve or request revisions, then send a message to continue."
                    } else {
                        pauseMessage = "Step \(stepIndex + 1)/\(workflow.count) complete (\(step.stepLabel ?? "done")). Review the \(reviewTarget), then send a message to continue."
                    }
                } else {
                    pauseMessage = "Step \(stepIndex + 1)/\(workflow.count) complete (\(step.stepLabel ?? "done")). Send a message to continue."
                }
                appendSystemMessage(pauseMessage)
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

    private func artifactGate(after stepIndex: Int, session: Session) -> WorkflowArtifactGate? {
        guard conversation.executionMode == .interactive else { return nil }
        guard stepIndex >= 0 && stepIndex < workflow.count - 1 else { return nil }

        let nextStep = workflow[stepIndex + 1]
        let nextSession = findSession(for: nextStep.agentId)
        let nextAgentName = nextSession?.agent?.name
        let step = workflow[stepIndex]

        if let explicitGate = step.artifactGate,
           gate(explicitGate, blocks: nextAgentName) {
            return explicitGate
        }

        return inferredArtifactGate(currentAgentName: session.agent?.name, nextAgentName: nextAgentName)
    }

    private func gate(_ gate: WorkflowArtifactGate, blocks downstreamAgentName: String?) -> Bool {
        guard let downstreamAgentName else { return false }
        guard !gate.blockedDownstreamAgentNames.isEmpty else { return true }
        return gate.blockedDownstreamAgentNames.contains(downstreamAgentName)
    }

    private func inferredArtifactGate(currentAgentName: String?, nextAgentName: String?) -> WorkflowArtifactGate? {
        guard let currentAgentName, let nextAgentName else { return nil }

        switch (currentAgentName, nextAgentName) {
        case ("Product Manager", "Coder"):
            return WorkflowArtifactGate(
                profile: "product-spec",
                approvalRequired: true,
                publishRepoDoc: true,
                blockedDownstreamAgentNames: ["Coder"]
            )
        case ("Orchestrator", "Coder"):
            return WorkflowArtifactGate(
                profile: "implementation-plan",
                approvalRequired: false,
                publishRepoDoc: false,
                blockedDownstreamAgentNames: ["Coder"]
            )
        case ("Designer", "Coder"), ("UX Designer", "Coder"), ("UX Designer", "Frontend Dev"):
            return WorkflowArtifactGate(
                profile: "ux-spec",
                approvalRequired: true,
                publishRepoDoc: true,
                blockedDownstreamAgentNames: [nextAgentName]
            )
        case ("Technical Lead", "Coder"), ("Technical Lead", "Backend Dev"), ("API Designer", "Backend Dev"):
            return WorkflowArtifactGate(
                profile: "architecture-decision",
                approvalRequired: true,
                publishRepoDoc: true,
                blockedDownstreamAgentNames: [nextAgentName]
            )
        case ("Tester", "DevOps"), ("Tester", "Release Manager"):
            return WorkflowArtifactGate(
                profile: "test-signoff",
                approvalRequired: true,
                publishRepoDoc: false,
                blockedDownstreamAgentNames: [nextAgentName]
            )
        default:
            return nil
        }
    }

    private func artifactReviewTarget(for profile: String) -> String {
        switch profile {
        case "product-spec":
            return "PRD and wireframes"
        case "implementation-plan":
            return "implementation plan and acceptance criteria"
        case "ux-spec":
            return "design spec, flows, and wireframes"
        case "architecture-decision":
            return "architecture decision and diagrams"
        case "api-contract":
            return "API contract and data-flow diagrams"
        case "test-signoff":
            return "test strategy or signoff summary"
        case "review-summary":
            return "review summary and blocking findings"
        case "research-brief":
            return "research brief and recommendations"
        case "release-plan":
            return "release checklist and rollout plan"
        default:
            return "artifacts"
        }
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
