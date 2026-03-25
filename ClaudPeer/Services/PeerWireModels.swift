import Foundation

/// JSON payload exchanged between ClaudPeer instances on the LAN (P2P v1).
struct WireAgentExport: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var agentDescription: String
    var systemPrompt: String
    var model: String
    var maxTurns: Int?
    var maxBudget: Double?
    var maxThinkingTokens: Int?
    var icon: String
    var color: String
    var defaultWorkingDirectory: String?
    var githubRepo: String?
    var githubDefaultBranch: String?
    var skillNames: [String]
    var extraMCPNames: [String]
    var permissionSetName: String?
}

struct WireGroupExport: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var groupDescription: String
    var icon: String
    var color: String
    var groupInstruction: String
    var defaultMission: String?
    var agentNames: [String]
}

struct WireAgentExportList: Codable, Sendable {
    var agents: [WireAgentExport]
    var groups: [WireGroupExport]?
}
