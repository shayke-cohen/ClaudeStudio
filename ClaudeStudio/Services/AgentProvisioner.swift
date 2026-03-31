import Foundation
import SwiftData

@MainActor
final class AgentProvisioner {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func provision(
        agent: Agent,
        mission: String?,
        workingDirOverride: String? = nil,
        providerOverride: String? = nil,
        modelOverride: String? = nil
    ) -> (AgentConfig, Session) {
        let session = Session(
            agent: agent,
            mission: mission,
            mode: .interactive,
            workingDirectory: resolveWorkingDirectory(override: workingDirOverride)
        )
        session.provider = AgentDefaults.resolveEffectiveProvider(
            sessionOverride: providerOverride,
            agentSelection: agent.provider
        )
        session.model = AgentDefaults.resolveEffectiveModel(
            sessionOverride: modelOverride,
            agentSelection: agent.model,
            provider: session.provider
        )

        return (buildConfig(agent: agent, session: session), session)
    }

    func config(for session: Session) -> AgentConfig? {
        guard let agent = session.agent else { return nil }
        return buildConfig(agent: agent, session: session)
    }

    private func buildConfig(agent: Agent, session: Session) -> AgentConfig {
        let skills = resolveSkills(ids: agent.skillIds)
        let mcpServers = resolveMCPServers(ids: resolveEffectiveMCPServerIDs(agent: agent, skills: skills))
        let permissions = resolvePermissions(id: agent.permissionSetId)

        let allowedTools = permissions?.allowRules ?? ["Read", "Write", "Bash", "Grep", "Glob"]

        let isInteractive = session.mode == .interactive

        var systemPrompt = agent.systemPrompt
        if let mission = session.mission {
            systemPrompt += "\n\n# Current Mission\n\(mission)\n"
        }

        return AgentConfig(
            name: agent.name,
            systemPrompt: systemPrompt,
            allowedTools: allowedTools,
            mcpServers: mcpServers.map { mcp in
                switch mcp.transport {
                case .stdio(let command, let args, let env):
                    return AgentConfig.MCPServerConfig(
                        name: mcp.name, command: command, args: args, env: env, url: nil
                    )
                case .http(let url, _):
                    return AgentConfig.MCPServerConfig(
                        name: mcp.name, command: nil, args: nil, env: nil, url: url
                    )
                }
            },
            provider: session.provider,
            model: session.model ?? AgentDefaults.resolveEffectiveModel(
                agentSelection: agent.model,
                provider: session.provider
            ),
            maxTurns: agent.maxTurns,
            maxBudget: agent.maxBudget,
            maxThinkingTokens: agent.maxThinkingTokens,
            workingDirectory: session.workingDirectory,
            skills: skills.map { AgentConfig.SkillContent(name: $0.name, content: $0.content) },
            interactive: isInteractive ? true : nil
        )
    }

    private func resolveWorkingDirectory(override: String?) -> String {
        if let explicit = override, !explicit.isEmpty { return explicit }
        return NSHomeDirectory() // defensive fallback — should always have override from worktree
    }

    private func resolveSkills(ids: [UUID]) -> [Skill] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Skill>(predicate: #Predicate { skill in
            ids.contains(skill.id) && skill.isEnabled
        })
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        let byId = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }

    private func resolveMCPServers(ids: [UUID]) -> [MCPServer] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<MCPServer>(predicate: #Predicate { mcp in
            ids.contains(mcp.id) && mcp.isEnabled
        })
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        let byId = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }

    private func resolveEffectiveMCPServerIDs(agent: Agent, skills: [Skill]) -> [UUID] {
        var ordered: [UUID] = []
        var seen = Set<UUID>()

        for id in agent.extraMCPServerIds where seen.insert(id).inserted {
            ordered.append(id)
        }

        for skill in skills {
            for id in skill.mcpServerIds where seen.insert(id).inserted {
                ordered.append(id)
            }
        }

        return ordered
    }

    private func resolvePermissions(id: UUID?) -> PermissionSet? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<PermissionSet>(predicate: #Predicate { perm in
            perm.id == id
        })
        return try? modelContext.fetch(descriptor).first
    }
}
