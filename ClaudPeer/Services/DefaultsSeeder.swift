import Foundation
import SwiftData

enum DefaultsSeeder {

    static let seededKey = "claudpeer.defaultsSeeded"

    static func seedIfNeeded(container: ModelContainer) {
        guard !InstanceConfig.userDefaults.bool(forKey: seededKey) else { return }

        let context = ModelContext(container)
        let permCount = (try? context.fetchCount(FetchDescriptor<PermissionSet>())) ?? 0
        if permCount > 0 { return }

        print("[DefaultsSeeder] First launch — seeding defaults")

        let permissions = seedPermissionPresets(into: context)
        let mcpServers = seedMCPServers(into: context)
        let skills = seedSkills(into: context)
        let templates = loadSystemPromptTemplates()
        seedAgents(into: context, permissions: permissions, mcpServers: mcpServers, skills: skills, templates: templates)

        do {
            try context.save()
            InstanceConfig.userDefaults.set(true, forKey: seededKey)
            print("[DefaultsSeeder] Seeding complete")
        } catch {
            print("[DefaultsSeeder] Failed to save: \(error)")
        }
    }

    // MARK: - Permission Presets

    @discardableResult
    private static func seedPermissionPresets(into context: ModelContext) -> [String: PermissionSet] {
        guard let data = loadResource(name: "DefaultPermissionPresets", ext: "json") else {
            print("[DefaultsSeeder] DefaultPermissionPresets.json not found")
            return [:]
        }

        struct PresetDTO: Decodable {
            let name: String
            let allowRules: [String]
            let denyRules: [String]
            let additionalDirectories: [String]
            let permissionMode: String
        }

        guard let dtos = try? JSONDecoder().decode([PresetDTO].self, from: data) else {
            print("[DefaultsSeeder] Failed to decode permission presets")
            return [:]
        }

        var map: [String: PermissionSet] = [:]
        for dto in dtos {
            let ps = PermissionSet(
                name: dto.name,
                allowRules: dto.allowRules,
                denyRules: dto.denyRules,
                permissionMode: dto.permissionMode
            )
            ps.additionalDirectories = dto.additionalDirectories
            context.insert(ps)
            map[dto.name] = ps
            print("[DefaultsSeeder]   Permission preset: \(dto.name)")
        }
        return map
    }

    // MARK: - MCP Servers

    private static func seedMCPServers(into context: ModelContext) -> [String: MCPServer] {
        guard let data = loadResource(name: "DefaultMCPs", ext: "json") else {
            print("[DefaultsSeeder] DefaultMCPs.json not found")
            return [:]
        }

        struct MCPDTO: Decodable {
            let name: String
            let serverDescription: String
            let transportKind: String
            let transportCommand: String?
            let transportArgs: [String]?
            let transportEnv: [String: String]?
            let transportUrl: String?
            let transportHeaders: [String: String]?
        }

        guard let dtos = try? JSONDecoder().decode([MCPDTO].self, from: data) else {
            print("[DefaultsSeeder] Failed to decode MCP servers")
            return [:]
        }

        var map: [String: MCPServer] = [:]
        for dto in dtos {
            let transport: MCPTransport
            if dto.transportKind == "stdio" {
                transport = .stdio(
                    command: dto.transportCommand ?? "",
                    args: dto.transportArgs ?? [],
                    env: dto.transportEnv ?? [:]
                )
            } else {
                transport = .http(
                    url: dto.transportUrl ?? "",
                    headers: dto.transportHeaders ?? [:]
                )
            }
            let server = MCPServer(name: dto.name, serverDescription: dto.serverDescription, transport: transport)
            context.insert(server)
            map[dto.name] = server
            print("[DefaultsSeeder]   MCP server: \(dto.name)")
        }
        return map
    }

    // MARK: - Skills

    private static func seedSkills(into context: ModelContext) -> [String: Skill] {
        let skillNames = [
            "peer-collaboration",
            "blackboard-patterns",
            "delegation-patterns",
            "workspace-collaboration",
            "agent-identity"
        ]

        var map: [String: Skill] = [:]
        for skillName in skillNames {
            guard let content = loadSkillContent(name: skillName) else {
                print("[DefaultsSeeder]   Skill not found: \(skillName)")
                continue
            }

            let metadata = parseSkillFrontmatter(content)
            let skill = Skill(
                name: metadata.name ?? skillName,
                skillDescription: metadata.description ?? "",
                category: metadata.category ?? "ClaudPeer",
                content: content
            )
            skill.triggers = metadata.triggers
            skill.source = .builtin
            context.insert(skill)
            map[skillName] = skill
            print("[DefaultsSeeder]   Skill: \(skillName)")
        }
        return map
    }

    // MARK: - System Prompt Templates

    private static func loadSystemPromptTemplates() -> [String: String] {
        let templateNames = ["specialist", "worker", "coordinator"]
        var templates: [String: String] = [:]
        for name in templateNames {
            if let content = loadTemplateContent(name: name) {
                templates[name] = content
                print("[DefaultsSeeder]   Template loaded: \(name)")
            } else {
                print("[DefaultsSeeder]   Template not found: \(name)")
            }
        }
        return templates
    }

    // MARK: - Agents

    private static func seedAgents(
        into context: ModelContext,
        permissions: [String: PermissionSet],
        mcpServers: [String: MCPServer],
        skills: [String: Skill],
        templates: [String: String]
    ) {
        let agentFiles = ["orchestrator", "coder", "reviewer", "researcher", "tester", "devops", "writer"]

        for fileName in agentFiles {
            guard let data = loadAgentResource(name: fileName) else {
                print("[DefaultsSeeder]   Agent JSON not found: \(fileName)")
                continue
            }

            guard let dto = try? JSONDecoder().decode(AgentDTO.self, from: data) else {
                print("[DefaultsSeeder]   Failed to decode agent: \(fileName)")
                continue
            }

            let systemPrompt = resolveSystemPrompt(dto: dto, templates: templates)
            let agent = Agent(
                name: dto.name,
                agentDescription: dto.agentDescription,
                systemPrompt: systemPrompt,
                model: dto.model,
                icon: dto.icon,
                color: dto.color
            )

            agent.instancePolicyKind = dto.instancePolicyKind
            agent.instancePolicyPoolMax = dto.instancePolicyPoolMax
            agent.maxTurns = dto.maxTurns
            agent.maxBudget = dto.maxBudget
            agent.origin = .builtin

            agent.skillIds = dto.skillNames.compactMap { skills[$0]?.id }
            agent.extraMCPServerIds = dto.mcpServerNames.compactMap { mcpServers[$0]?.id }
            if let ps = permissions[dto.permissionSetName] {
                agent.permissionSetId = ps.id
            }

            context.insert(agent)
            print("[DefaultsSeeder]   Agent: \(dto.name) (skills: \(agent.skillIds.count), MCPs: \(agent.extraMCPServerIds.count))")
        }
    }

    // MARK: - Template Resolution

    private static func resolveSystemPrompt(dto: AgentDTO, templates: [String: String]) -> String {
        guard let templateName = dto.systemPromptTemplate,
              let template = templates[templateName] else {
            return ""
        }

        var prompt = template
        for (key, value) in dto.systemPromptVariables ?? [:] {
            prompt = prompt.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        prompt = prompt.replacingOccurrences(of: "{{constraints}}", with: "")
        prompt = prompt.replacingOccurrences(of: "{{polling_interval}}", with: "30000")
        return prompt
    }

    // MARK: - DTOs

    private struct AgentDTO: Decodable {
        let name: String
        let agentDescription: String
        let model: String
        let icon: String
        let color: String
        let instancePolicyKind: String
        let instancePolicyPoolMax: Int?
        let skillNames: [String]
        let mcpServerNames: [String]
        let permissionSetName: String
        let systemPromptTemplate: String?
        let systemPromptVariables: [String: String]?
        let maxTurns: Int?
        let maxBudget: Double?
    }

    private struct SkillFrontmatter {
        var name: String?
        var description: String?
        var category: String?
        var triggers: [String] = []
    }

    // MARK: - Frontmatter Parsing

    private static func parseSkillFrontmatter(_ content: String) -> SkillFrontmatter {
        var fm = SkillFrontmatter()
        guard content.hasPrefix("---") else { return fm }
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else { return fm }
        let yaml = parts[1]

        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                fm.name = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("description:") {
                fm.description = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("category:") {
                fm.category = trimmed.dropFirst(9).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- ") && !trimmed.contains(":") {
                fm.triggers.append(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))
            }
        }
        return fm
    }

    // MARK: - Resource Loading

    private static func loadResource(name: String, ext: String) -> Data? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return try? Data(contentsOf: url)
        }
        let fallbackPaths = [
            "\(NSHomeDirectory())/ClaudPeer/ClaudPeer/Resources/\(name).\(ext)",
            "\(FileManager.default.currentDirectoryPath)/ClaudPeer/Resources/\(name).\(ext)"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try? Data(contentsOf: URL(fileURLWithPath: path))
            }
        }
        return nil
    }

    private static func loadSkillContent(name: String) -> String? {
        if let url = Bundle.main.url(forResource: "SKILL", withExtension: "md", subdirectory: "DefaultSkills/\(name)") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        let fallbackPaths = [
            "\(NSHomeDirectory())/ClaudPeer/ClaudPeer/Resources/DefaultSkills/\(name)/SKILL.md",
            "\(FileManager.default.currentDirectoryPath)/ClaudPeer/Resources/DefaultSkills/\(name)/SKILL.md"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            }
        }
        return nil
    }

    private static func loadAgentResource(name: String) -> Data? {
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "DefaultAgents") {
            return try? Data(contentsOf: url)
        }
        let fallbackPaths = [
            "\(NSHomeDirectory())/ClaudPeer/ClaudPeer/Resources/DefaultAgents/\(name).json",
            "\(FileManager.default.currentDirectoryPath)/ClaudPeer/Resources/DefaultAgents/\(name).json"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try? Data(contentsOf: URL(fileURLWithPath: path))
            }
        }
        return nil
    }

    private static func loadTemplateContent(name: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "SystemPromptTemplates") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        let fallbackPaths = [
            "\(NSHomeDirectory())/ClaudPeer/ClaudPeer/Resources/SystemPromptTemplates/\(name).md",
            "\(FileManager.default.currentDirectoryPath)/ClaudPeer/Resources/SystemPromptTemplates/\(name).md"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            }
        }
        return nil
    }
}
