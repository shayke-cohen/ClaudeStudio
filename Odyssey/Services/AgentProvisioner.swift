import Foundation
import OSLog
import SwiftData

@MainActor
final class AgentProvisioner {
    struct RuntimeModeSettings: Sendable, Equatable {
        let interactive: Bool
        let instancePolicy: String?
        let instancePolicyPoolMax: Int?
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func provision(
        agent: Agent,
        mission: String?,
        mode: SessionMode = .interactive,
        workingDirOverride: String? = nil,
        providerOverride: String? = nil,
        modelOverride: String? = nil
    ) -> (AgentConfig, Session) {
        let resolvedDir = resolveWorkingDirectory(override: workingDirOverride, agent: agent)
        ensureOdysseyHomeDir(resolvedDir)
        GitService.initIfNeeded(at: URL(fileURLWithPath: resolvedDir))
        let session = Session(
            agent: agent,
            mission: mission,
            mode: mode,
            workingDirectory: resolvedDir
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
        let wd = effectiveWorkingDirectory(agent: agent, session: session)
        return buildConfig(agent: agent, session: session, workingDirectory: wd)
    }

    /// Returns the working directory to use for a session, honoring agent home dirs
    /// over any project dir stored on the session, but preserving explicit worktree paths.
    private func effectiveWorkingDirectory(agent: Agent, session: Session) -> String {
        let worktreesBase = NSString(string: "~/.odyssey/worktrees").expandingTildeInPath
        let groupsBase = NSString(string: "~/.odyssey/groups").expandingTildeInPath
        let isWorktree = session.workingDirectory.hasPrefix(worktreesBase + "/")
        let isGroupDir = session.workingDirectory.hasPrefix(groupsBase + "/")
        if isGroupDir {
            ensureOdysseyHomeDir(session.workingDirectory)
            return session.workingDirectory
        }
        if !isWorktree, let agentDir = agent.defaultWorkingDirectory, !agentDir.isEmpty {
            let path = NSString(string: agentDir).expandingTildeInPath
            ensureOdysseyHomeDir(path)
            return path
        }
        return session.workingDirectory
    }

    private func buildConfig(agent: Agent, session: Session, workingDirectory: String? = nil) -> AgentConfig {
        let skills = resolveSkills(ids: agent.skillIds)
        let mcpServers = filteredMCPServers(
            resolveMCPServers(ids: resolveEffectiveMCPServerIDs(agent: agent, skills: skills)),
            provider: session.provider,
            model: session.model
        )
        let permissions = resolvePermissions(id: agent.permissionSetId)

        let allowedTools = permissions?.allowRules ?? ["Read", "Write", "Bash", "Grep", "Glob"]

        let runtimeSettings = Self.runtimeModeSettings(agent: agent, mode: session.mode)

        var systemPrompt = agent.systemPrompt
        if let mission = session.mission {
            systemPrompt += "\n\n# Current Mission\n\(mission)\n"
        }

        let resolvedWD = workingDirectory ?? session.workingDirectory

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
            workingDirectory: resolvedWD,
            skills: skills.map { AgentConfig.SkillContent(name: $0.name, content: $0.content) },
            interactive: runtimeSettings.interactive ? true : nil,
            instancePolicy: runtimeSettings.instancePolicy,
            instancePolicyPoolMax: runtimeSettings.instancePolicyPoolMax
        )
    }

    static func runtimeModeSettings(agent: Agent?, mode: SessionMode) -> RuntimeModeSettings {
        switch mode {
        case .worker:
            return RuntimeModeSettings(
                interactive: false,
                instancePolicy: AgentInstancePolicy.singleton.rawValue,
                instancePolicyPoolMax: nil
            )
        case .autonomous:
            return RuntimeModeSettings(
                interactive: false,
                instancePolicy: AgentInstancePolicy.spawn.rawValue,
                instancePolicyPoolMax: nil
            )
        case .interactive:
            guard let agent else {
                return RuntimeModeSettings(interactive: true, instancePolicy: nil, instancePolicyPoolMax: nil)
            }

            let instancePolicy: String?
            switch agent.instancePolicy {
            case .agentDefault:
                instancePolicy = nil
            case .spawn, .singleton, .pool:
                instancePolicy = agent.instancePolicy.rawValue
            }

            let poolMax = agent.instancePolicy == .pool ? agent.instancePolicyPoolMax : nil
            return RuntimeModeSettings(
                interactive: true,
                instancePolicy: instancePolicy,
                instancePolicyPoolMax: poolMax
            )
        }
    }

    private func resolveWorkingDirectory(override: String?, agent: Agent) -> String {
        if let explicit = override, !explicit.isEmpty {
            return NSString(string: explicit).expandingTildeInPath
        }
        if let agentDefault = agent.defaultWorkingDirectory, !agentDefault.isEmpty {
            return NSString(string: agentDefault).expandingTildeInPath
        }
        return NSHomeDirectory()
    }

    private func ensureOdysseyHomeDir(_ path: String) {
        let odysseyHome = NSString(string: "~/.odyssey").expandingTildeInPath
        guard path.hasPrefix(odysseyHome + "/") else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        let gitDir = (path as NSString).appendingPathComponent(".git")
        guard !fm.fileExists(atPath: gitDir) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
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

    private func filteredMCPServers(_ servers: [MCPServer], provider: String, model: String?) -> [MCPServer] {
        let usesLocalClaudeLoop = provider == ProviderSelection.claude.rawValue
            && AgentDefaults.isOllamaBackedClaudeModel(model)
        guard provider == ProviderSelection.mlx.rawValue
            || provider == ProviderSelection.foundation.rawValue
            || usesLocalClaudeLoop else {
            return servers
        }

        // Local providers and Ollama-backed Claude sessions keep built-in tools, but we skip the
        // heavyweight ambient MCPs that can block local session startup while they bootstrap
        // external runtimes.
        let blockedNames = Set(["Argus", "AppXray", "Octocode"])
        return servers.filter { !blockedNames.contains($0.name) }
    }

    private func resolvePermissions(id: UUID?) -> PermissionSet? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<PermissionSet>(predicate: #Predicate { perm in
            perm.id == id
        })
        return try? modelContext.fetch(descriptor).first
    }
}
