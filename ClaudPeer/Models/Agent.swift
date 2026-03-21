import Foundation
import SwiftData

enum InstancePolicy: Codable, Sendable, Hashable {
    case spawn
    case singleton
    case pool(max: Int)
}

enum AgentOrigin: Codable, Sendable, Hashable {
    case local
    case peer(peerId: UUID)
    case imported
}

@Model
final class Agent {
    var id: UUID
    var name: String
    var agentDescription: String
    var systemPrompt: String
    var skillIds: [UUID]
    var mcpServerIds: [UUID]
    var permissionSetId: UUID?
    var model: String
    var maxTurns: Int?
    var maxBudget: Double?
    var icon: String
    var color: String
    var instancePolicy: InstancePolicy
    var defaultWorkingDirectory: String?
    var githubRepo: String?
    var githubDefaultBranch: String?
    var origin: AgentOrigin
    var isShared: Bool
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Session.agent)
    var sessions: [Session] = []

    init(
        name: String,
        agentDescription: String = "",
        systemPrompt: String = "",
        model: String = "sonnet",
        icon: String = "cpu",
        color: String = "blue"
    ) {
        self.id = UUID()
        self.name = name
        self.agentDescription = agentDescription
        self.systemPrompt = systemPrompt
        self.skillIds = []
        self.mcpServerIds = []
        self.model = model
        self.maxTurns = nil
        self.maxBudget = nil
        self.icon = icon
        self.color = color
        self.instancePolicy = .spawn
        self.origin = .local
        self.isShared = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
