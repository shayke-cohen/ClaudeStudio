import Foundation

struct WorkflowArtifactGate: Codable, Sendable {
    var profile: String
    var approvalRequired: Bool
    var publishRepoDoc: Bool
    var blockedDownstreamAgentNames: [String]
}

struct WorkflowStep: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var agentId: UUID
    var instruction: String
    var condition: String?
    var autoAdvance: Bool
    var stepLabel: String?
    var artifactGate: WorkflowArtifactGate?

    init(
        id: UUID = UUID(),
        agentId: UUID,
        instruction: String,
        condition: String? = nil,
        autoAdvance: Bool,
        stepLabel: String? = nil,
        artifactGate: WorkflowArtifactGate? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.instruction = instruction
        self.condition = condition
        self.autoAdvance = autoAdvance
        self.stepLabel = stepLabel
        self.artifactGate = artifactGate
    }
}
