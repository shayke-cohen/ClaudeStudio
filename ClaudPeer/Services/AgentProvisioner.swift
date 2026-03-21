import Foundation
import SwiftData

@MainActor
final class AgentProvisioner {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func provision(agent: Agent, mission: String?, workingDirOverride: String? = nil) -> (AgentConfig, Session) {
        let session = Session(
            agent: agent,
            mission: mission,
            mode: .interactive,
            workingDirectory: resolveWorkingDirectory(agent: agent, override: workingDirOverride),
            workspaceType: resolveWorkspaceType(agent: agent, override: workingDirOverride)
        )

        let skills = resolveSkills(ids: agent.skillIds)
        let mcpServers = resolveMCPServers(ids: agent.extraMCPServerIds)
        let permissions = resolvePermissions(id: agent.permissionSetId)

        var allowedTools = permissions?.allowRules ?? ["Read", "Write", "Bash", "Grep", "Glob"]
        if agent.githubRepo != nil {
            if !allowedTools.contains("Bash(gh *)") { allowedTools.append("Bash(gh *)") }
            if !allowedTools.contains("Bash(git *)") { allowedTools.append("Bash(git *)") }
        }
        allowedTools.append(contentsOf: [
            "peer_chat_start", "peer_chat_reply", "peer_chat_close", "peer_chat_invite",
            "peer_send_message", "peer_delegate_task", "peer_receive_messages",
            "peer_list_agents", "peer_broadcast",
            "blackboard_read", "blackboard_write", "blackboard_query", "blackboard_subscribe",
            "workspace_create", "workspace_join", "workspace_list",
        ])

        var systemPrompt = agent.systemPrompt
        if !skills.isEmpty {
            systemPrompt += "\n\n# Available Skills\n"
            for skill in skills {
                systemPrompt += "\n## \(skill.name)\n\(skill.content)\n"
            }
        }
        if let repo = agent.githubRepo {
            systemPrompt += "\n\n# GitHub Repository\nThis agent is linked to: \(repo)"
            if let branch = agent.githubDefaultBranch {
                systemPrompt += " (branch: \(branch))"
            }
            systemPrompt += "\n"
        }
        if let mission = mission {
            systemPrompt += "\n\n# Current Mission\n\(mission)\n"
        }

        let config = AgentConfig(
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
            model: agent.model,
            maxTurns: agent.maxTurns,
            maxBudget: agent.maxBudget,
            workingDirectory: session.workingDirectory,
            skills: skills.map { AgentConfig.SkillContent(name: $0.name, content: $0.content) }
        )

        return (config, session)
    }

    private func resolveWorkingDirectory(agent: Agent, override: String?) -> String {
        if let explicit = override, !explicit.isEmpty { return explicit }
        if let repo = agent.githubRepo, !repo.isEmpty {
            let repoName = repo.split(separator: "/").suffix(2).joined(separator: "-")
            return "\(NSHomeDirectory())/.claudpeer/repos/\(repoName)"
        }
        if let defaultDir = agent.defaultWorkingDirectory, !defaultDir.isEmpty { return defaultDir }
        return "\(NSHomeDirectory())/.claudpeer/sandboxes/\(UUID().uuidString)"
    }

    private func resolveWorkspaceType(agent: Agent, override: String?) -> WorkspaceType {
        if let explicit = override, !explicit.isEmpty { return .explicit(path: explicit) }
        if let repo = agent.githubRepo, !repo.isEmpty { return .githubClone(repoUrl: repo) }
        if agent.defaultWorkingDirectory != nil { return .agentDefault }
        return .ephemeral
    }

    private func resolveSkills(ids: [UUID]) -> [Skill] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Skill>(predicate: #Predicate { skill in
            ids.contains(skill.id)
        })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func resolveMCPServers(ids: [UUID]) -> [MCPServer] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<MCPServer>(predicate: #Predicate { mcp in
            ids.contains(mcp.id)
        })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func resolvePermissions(id: UUID?) -> PermissionSet? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<PermissionSet>(predicate: #Predicate { perm in
            perm.id == id
        })
        return try? modelContext.fetch(descriptor).first
    }
}
