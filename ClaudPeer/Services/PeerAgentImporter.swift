import Foundation
import SwiftData

struct PeerImportResult {
    let agent: Agent
    let missingSkills: [String]
    let missingMCPs: [String]
    let missingPermission: String?
}

@MainActor
enum PeerAgentImporter {
    static func importFromWire(_ w: WireAgentExport, peerDisplayName: String, modelContext: ModelContext) throws -> PeerImportResult {
        // Duplicate guard: skip if an agent with the same original ID was already imported from a peer
        let allAgents = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
        if allAgents.contains(where: { $0.originKind == "peer" && $0.originRemoteId == w.id }) {
            throw PeerImportError.alreadyImported(name: w.name)
        }

        let skills = try modelContext.fetch(FetchDescriptor<Skill>())
        let mcps = try modelContext.fetch(FetchDescriptor<MCPServer>())
        let perms = try modelContext.fetch(FetchDescriptor<PermissionSet>())

        let skillByName = Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0) })
        let mcpByName = Dictionary(uniqueKeysWithValues: mcps.map { ($0.name, $0) })
        let permByName = Dictionary(uniqueKeysWithValues: perms.map { ($0.name, $0) })

        let missingSkills = w.skillNames.filter { skillByName[$0] == nil }
        let missingMCPs = w.extraMCPNames.filter { mcpByName[$0] == nil }
        let missingPerm: String? = w.permissionSetName.flatMap { permByName[$0] == nil ? $0 : nil }

        let uniqueName = disambiguateName(w.name, existing: allAgents)
        let agent = Agent(
            name: uniqueName,
            agentDescription: w.agentDescription,
            systemPrompt: w.systemPrompt,
            model: w.model,
            icon: w.icon,
            color: w.color
        )
        agent.skillIds = w.skillNames.compactMap { skillByName[$0]?.id }
        agent.extraMCPServerIds = w.extraMCPNames.compactMap { mcpByName[$0]?.id }
        agent.permissionSetId = w.permissionSetName.flatMap { permByName[$0]?.id }
        agent.maxTurns = w.maxTurns
        agent.maxBudget = w.maxBudget
        agent.maxThinkingTokens = w.maxThinkingTokens
        agent.defaultWorkingDirectory = w.defaultWorkingDirectory
        agent.githubRepo = w.githubRepo
        agent.githubDefaultBranch = w.githubDefaultBranch
        agent.instancePolicyKind = w.instancePolicyKind.isEmpty ? "spawn" : w.instancePolicyKind
        agent.instancePolicyPoolMax = w.instancePolicyPoolMax
        agent.origin = .peer(peerName: peerDisplayName)
        agent.originRemoteId = w.id
        agent.catalogId = nil

        modelContext.insert(agent)
        try modelContext.save()
        return PeerImportResult(agent: agent, missingSkills: missingSkills, missingMCPs: missingMCPs, missingPermission: missingPerm)
    }

    private static func disambiguateName(_ base: String, existing: [Agent]) -> String {
        let names = Set(existing.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) (\(n))") {
            n += 1
        }
        return "\(base) (\(n))"
    }

    // MARK: - Group Import

    static func importGroupFromWire(_ w: WireGroupExport, peerDisplayName: String, modelContext: ModelContext) throws -> AgentGroup {
        let allGroups = (try? modelContext.fetch(FetchDescriptor<AgentGroup>())) ?? []
        if allGroups.contains(where: { $0.originKind == "peer" && $0.originRemoteId == w.id }) {
            throw PeerImportError.alreadyImported(name: w.name)
        }

        let allAgents = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
        let agentByName = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.name, $0) })
        let resolvedIds = w.agentNames.compactMap { agentByName[$0]?.id }

        let groupNames = Set(allGroups.map(\.name))
        let uniqueName = groupNames.contains(w.name) ? "\(w.name) (\(peerDisplayName))" : w.name

        let group = AgentGroup(
            name: uniqueName,
            groupDescription: w.groupDescription,
            icon: w.icon,
            color: w.color,
            groupInstruction: w.groupInstruction,
            defaultMission: w.defaultMission,
            agentIds: resolvedIds,
            sortOrder: allGroups.count
        )
        group.origin = .peer(peerName: peerDisplayName)
        group.originRemoteId = w.id

        modelContext.insert(group)
        try modelContext.save()
        return group
    }
}

enum PeerImportError: LocalizedError {
    case alreadyImported(name: String)

    var errorDescription: String? {
        switch self {
        case .alreadyImported(let name):
            return "\"\(name)\" was already imported from this peer."
        }
    }
}
