import Foundation
import SwiftData

struct IssueContext: Sendable {
    let number: Int
    let title: String
    let body: String
    let labels: [String]
}

@MainActor
final class AgentProvisioner {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func provision(agent: Agent, mission: String?, workingDirOverride: String? = nil, worktreeBranch: String? = nil, issueContext: IssueContext? = nil) -> (AgentConfig, Session) {
        let session = Session(
            agent: agent,
            mission: mission,
            mode: .interactive,
            workingDirectory: resolveWorkingDirectory(agent: agent, override: workingDirOverride, worktreeBranch: worktreeBranch),
            workspaceType: resolveWorkspaceType(agent: agent, override: workingDirOverride, worktreeBranch: worktreeBranch)
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
            "peer_chat_start", "peer_chat_reply", "peer_chat_listen",
            "peer_chat_close", "peer_chat_invite",
            "peer_send_message", "peer_delegate_task", "peer_receive_messages",
            "peer_list_agents", "peer_broadcast",
            "blackboard_read", "blackboard_write", "blackboard_query", "blackboard_subscribe",
            "workspace_create", "workspace_join", "workspace_list",
        ])

        let isInteractive = session.mode == .interactive
        if isInteractive {
            allowedTools.append("ask_user")
        }

        var systemPrompt = agent.systemPrompt
        if !skills.isEmpty {
            systemPrompt += "\n\n# Available Skills\n"
            for skill in skills {
                systemPrompt += "\n## \(skill.name)\n\(skill.content)\n"
            }
        }
        if let wtBranch = worktreeBranch, let repo = agent.githubRepo {
            systemPrompt += "\n\n# Git Worktree\nWorking in an isolated worktree on branch: \(wtBranch)\nBase repository: \(repo)\n"
        } else if let repo = agent.githubRepo {
            systemPrompt += "\n\n# GitHub Repository\nThis agent is linked to: \(repo)"
            if let branch = agent.githubDefaultBranch {
                systemPrompt += " (branch: \(branch))"
            }
            systemPrompt += "\n"
        }
        if let issue = issueContext {
            systemPrompt += "\n\n# GitHub Issue #\(issue.number)\n"
            systemPrompt += "**\(issue.title)**\n\n\(issue.body)\n"
            if !issue.labels.isEmpty {
                systemPrompt += "\nLabels: \(issue.labels.joined(separator: ", "))\n"
            }
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
            maxThinkingTokens: agent.maxThinkingTokens,
            workingDirectory: session.workingDirectory,
            skills: skills.map { AgentConfig.SkillContent(name: $0.name, content: $0.content) },
            interactive: isInteractive ? true : nil
        )

        return (config, session)
    }

    private func resolveWorkingDirectory(agent: Agent, override: String?, worktreeBranch: String? = nil) -> String {
        if let explicit = override, !explicit.isEmpty { return explicit }
        if let branch = worktreeBranch, let repo = agent.githubRepo, !repo.isEmpty {
            return WorkspaceResolver.worktreeDestinationPath(repoInput: repo, branch: branch)
        }
        if let repo = agent.githubRepo, !repo.isEmpty {
            return WorkspaceResolver.cloneDestinationPath(repoInput: repo)
        }
        if let defaultDir = agent.defaultWorkingDirectory, !defaultDir.isEmpty {
            // Expand ~ to home directory
            if defaultDir.hasPrefix("~/") {
                return NSHomeDirectory() + String(defaultDir.dropFirst(1))
            }
            return defaultDir
        }
        let sandboxPath = "\(NSHomeDirectory())/.claudpeer/sandboxes/\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: sandboxPath, withIntermediateDirectories: true, attributes: nil
        )
        return sandboxPath
    }

    private func resolveWorkspaceType(agent: Agent, override: String?, worktreeBranch: String? = nil) -> WorkspaceType {
        if let explicit = override, !explicit.isEmpty { return .explicit(path: explicit) }
        if let branch = worktreeBranch, let repo = agent.githubRepo, !repo.isEmpty {
            return .worktree(repoUrl: repo, branch: branch)
        }
        if let repo = agent.githubRepo, !repo.isEmpty { return .githubClone(repoUrl: repo) }
        if agent.defaultWorkingDirectory != nil { return .agentDefault }
        return .ephemeral
    }

    private func resolveSkills(ids: [UUID]) -> [Skill] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Skill>(predicate: #Predicate { skill in
            ids.contains(skill.id) && skill.isEnabled
        })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func resolveMCPServers(ids: [UUID]) -> [MCPServer] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<MCPServer>(predicate: #Predicate { mcp in
            ids.contains(mcp.id) && mcp.isEnabled
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
