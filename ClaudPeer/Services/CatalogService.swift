import Foundation
import SwiftData

struct CatalogMCP: Codable, Identifiable {
    let catalogId: String
    let name: String
    let description: String
    let category: String
    let icon: String
    let transport: CatalogTransport
    let popularity: Int
    let tags: [String]
    let homepage: String

    var id: String { catalogId }
}

struct CatalogTransport: Codable {
    let kind: String
    let command: String?
    let args: [String]?
    let envKeys: [String]?
    let url: String?
    let headerKeys: [String]?
}

struct CatalogSkill: Codable, Identifiable {
    let catalogId: String
    let name: String
    let description: String
    let category: String
    let icon: String
    let requiredMCPs: [String]
    let triggers: [String]
    let tags: [String]
    var content: String = ""

    var id: String { catalogId }

    private enum CodingKeys: String, CodingKey {
        case catalogId, name, description, category, icon, requiredMCPs, triggers, tags
    }
}

struct CatalogAgent: Codable, Identifiable {
    let catalogId: String
    let name: String
    let description: String
    let category: String
    let icon: String
    let color: String
    let model: String
    let instancePolicy: String
    let requiredSkills: [String]
    let extraMCPs: [String]
    let systemPromptTemplate: String
    let systemPromptVariables: [String: String]
    let tags: [String]
    var systemPrompt: String = ""

    var id: String { catalogId }

    private enum CodingKeys: String, CodingKey {
        case catalogId, name, description, category, icon, color, model
        case instancePolicy, requiredSkills, extraMCPs
        case systemPromptTemplate, systemPromptVariables, tags
    }
}

@MainActor
final class CatalogService {
    static let shared = CatalogService()

    private var mcpCatalog: [CatalogMCP] = []
    private var skillCatalog: [CatalogSkill] = []
    private var agentCatalog: [CatalogAgent] = []

    private init() {
        loadCatalogs()
    }

    private func loadCatalogs() {
        agentCatalog = loadAgentItems()
        skillCatalog = loadSkillItems()
        mcpCatalog = loadCatalogItems(directory: "mcps")
    }

    private func loadCatalogItems<T: Decodable>(directory: String) -> [T] {
        guard let ids: [String] = loadJSON(directory: directory, name: "index") else { return [] }
        return ids.compactMap { loadJSON(directory: directory, name: $0) }
    }

    private func loadAgentItems() -> [CatalogAgent] {
        guard let ids: [String] = loadJSON(directory: "agents", name: "index") else { return [] }
        return ids.compactMap { id -> CatalogAgent? in
            guard var agent: CatalogAgent = loadJSON(directory: "agents", name: id) else { return nil }
            agent.systemPrompt = loadMarkdown(directory: "agents", name: id) ?? ""
            return agent
        }
    }

    private func loadSkillItems() -> [CatalogSkill] {
        guard let ids: [String] = loadJSON(directory: "skills", name: "index") else { return [] }
        return ids.compactMap { id -> CatalogSkill? in
            guard var skill: CatalogSkill = loadJSON(directory: "skills", name: id) else { return nil }
            skill.content = loadMarkdown(directory: "skills", name: id) ?? ""
            return skill
        }
    }

    private func loadJSON<T: Decodable>(directory: String, name: String) -> T? {
        let subdirectory = "Catalog/\(directory)"
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory) {
            return decodeJSON(from: url)
        }
        for base in catalogSearchPaths() {
            let path = "\(base)/\(directory)/\(name).json"
            if FileManager.default.fileExists(atPath: path) {
                return decodeJSON(from: URL(fileURLWithPath: path))
            }
        }
        return nil
    }

    private func loadMarkdown(directory: String, name: String) -> String? {
        let subdirectory = "Catalog/\(directory)"
        if let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: subdirectory) {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        for base in catalogSearchPaths() {
            let path = "\(base)/\(directory)/\(name).md"
            if FileManager.default.fileExists(atPath: path) {
                return try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            }
        }
        return nil
    }

    private func catalogSearchPaths() -> [String] {
        [
            "\(NSHomeDirectory())/ClaudPeer/ClaudPeer/Resources/Catalog",
            Bundle.main.bundlePath + "/Contents/Resources/Catalog"
        ]
    }

    private func decodeJSON<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Catalog Access

    func allMCPs() -> [CatalogMCP] { mcpCatalog }
    func allSkills() -> [CatalogSkill] { skillCatalog }
    func allAgents() -> [CatalogAgent] { agentCatalog }

    func mcpCategories() -> [String] {
        Array(Set(mcpCatalog.map(\.category))).sorted()
    }

    func skillCategories() -> [String] {
        Array(Set(skillCatalog.map(\.category))).sorted()
    }

    func agentCategories() -> [String] {
        Array(Set(agentCatalog.map(\.category))).sorted()
    }

    func findMCP(_ catalogId: String) -> CatalogMCP? {
        mcpCatalog.first { $0.catalogId == catalogId }
    }

    func findSkill(_ catalogId: String) -> CatalogSkill? {
        skillCatalog.first { $0.catalogId == catalogId }
    }

    func findAgent(_ catalogId: String) -> CatalogAgent? {
        agentCatalog.first { $0.catalogId == catalogId }
    }

    // MARK: - Dependency Resolution

    struct AgentDependencies {
        let skills: [CatalogSkill]
        let mcps: [CatalogMCP]
        let missingSkillIds: [String]
        let missingMCPIds: [String]
    }

    func resolveDependencies(forAgent agent: CatalogAgent, context: ModelContext) -> AgentDependencies {
        var neededSkills: [CatalogSkill] = []
        var neededMCPIds: Set<String> = []
        var missingSkillIds: [String] = []

        for skillId in agent.requiredSkills {
            if let skill = findSkill(skillId) {
                if !isInstalled(catalogId: skillId, context: context) {
                    neededSkills.append(skill)
                }
                for mcpId in skill.requiredMCPs {
                    if !isInstalled(catalogId: mcpId, context: context) {
                        neededMCPIds.insert(mcpId)
                    }
                }
            } else {
                missingSkillIds.append(skillId)
            }
        }

        for mcpId in agent.extraMCPs {
            if !isInstalled(catalogId: mcpId, context: context) {
                neededMCPIds.insert(mcpId)
            }
        }

        var neededMCPs: [CatalogMCP] = []
        var missingMCPIds: [String] = []
        for mcpId in neededMCPIds.sorted() {
            if let mcp = findMCP(mcpId) {
                neededMCPs.append(mcp)
            } else {
                missingMCPIds.append(mcpId)
            }
        }

        return AgentDependencies(
            skills: neededSkills,
            mcps: neededMCPs,
            missingSkillIds: missingSkillIds,
            missingMCPIds: missingMCPIds
        )
    }

    func resolveDependencies(forSkill skill: CatalogSkill, context: ModelContext) -> [CatalogMCP] {
        skill.requiredMCPs.compactMap { mcpId in
            guard !isInstalled(catalogId: mcpId, context: context) else { return nil }
            return findMCP(mcpId)
        }
    }

    // MARK: - Install

    @discardableResult
    func installMCP(_ catalogId: String, into context: ModelContext) -> MCPServer? {
        guard let entry = findMCP(catalogId) else { return nil }
        if let existing = findInstalledMCP(catalogId: catalogId, context: context) { return existing }

        let transport: MCPTransport
        if entry.transport.kind == "stdio" {
            transport = .stdio(
                command: entry.transport.command ?? "npx",
                args: entry.transport.args ?? [],
                env: [:]
            )
        } else {
            transport = .http(url: entry.transport.url ?? "", headers: [:])
        }

        let server = MCPServer(name: entry.name, serverDescription: entry.description, transport: transport)
        server.catalogId = catalogId
        context.insert(server)
        return server
    }

    @discardableResult
    func installSkill(_ catalogId: String, into context: ModelContext, installMCPs: Bool = true) -> Skill? {
        guard let entry = findSkill(catalogId) else { return nil }
        if let existing = findInstalledSkill(catalogId: catalogId, context: context) { return existing }

        if installMCPs {
            for mcpId in entry.requiredMCPs {
                installMCP(mcpId, into: context)
            }
        }

        let mcpUUIDs = entry.requiredMCPs.compactMap { mcpId in
            findInstalledMCP(catalogId: mcpId, context: context)?.id
        }

        let skill = Skill(name: entry.name, skillDescription: entry.description, category: entry.category, content: entry.content)
        skill.triggers = entry.triggers
        skill.mcpServerIds = mcpUUIDs
        skill.catalogId = catalogId
        skill.sourceKind = "catalog"
        context.insert(skill)
        return skill
    }

    @discardableResult
    func installAgent(_ catalogId: String, into context: ModelContext) -> Agent? {
        guard let entry = findAgent(catalogId) else { return nil }
        if let existing = findInstalledAgent(catalogId: catalogId, context: context) { return existing }

        for skillId in entry.requiredSkills {
            installSkill(skillId, into: context)
        }

        let skillUUIDs = entry.requiredSkills.compactMap { skillId in
            findInstalledSkill(catalogId: skillId, context: context)?.id
        }

        let extraMCPUUIDs = entry.extraMCPs.compactMap { mcpId -> UUID? in
            installMCP(mcpId, into: context)
            return findInstalledMCP(catalogId: mcpId, context: context)?.id
        }

        let agent = Agent(
            name: entry.name,
            agentDescription: entry.description,
            systemPrompt: entry.systemPrompt,
            model: entry.model,
            icon: entry.icon,
            color: entry.color
        )
        agent.skillIds = skillUUIDs
        agent.extraMCPServerIds = extraMCPUUIDs
        agent.catalogId = catalogId
        agent.origin = .builtin

        if entry.instancePolicy == "singleton" {
            agent.instancePolicy = .singleton
        } else if entry.instancePolicy.hasPrefix("pool:") {
            let max = Int(entry.instancePolicy.replacingOccurrences(of: "pool:", with: "")) ?? 3
            agent.instancePolicy = .pool(max: max)
        }

        context.insert(agent)
        return agent
    }

    // MARK: - Uninstall

    func uninstallAgent(catalogId: String, context: ModelContext) {
        if let agent = findInstalledAgent(catalogId: catalogId, context: context) {
            context.delete(agent)
        }
    }

    func uninstallSkill(catalogId: String, context: ModelContext) {
        if let skill = findInstalledSkill(catalogId: catalogId, context: context) {
            context.delete(skill)
        }
    }

    func uninstallMCP(catalogId: String, context: ModelContext) {
        if let mcp = findInstalledMCP(catalogId: catalogId, context: context) {
            context.delete(mcp)
        }
    }

    // MARK: - Query Helpers

    func isInstalled(catalogId: String, context: ModelContext) -> Bool {
        findInstalledMCP(catalogId: catalogId, context: context) != nil ||
        findInstalledSkill(catalogId: catalogId, context: context) != nil ||
        findInstalledAgent(catalogId: catalogId, context: context) != nil
    }

    func isMCPInstalled(_ catalogId: String, context: ModelContext) -> Bool {
        findInstalledMCP(catalogId: catalogId, context: context) != nil
    }

    func isSkillInstalled(_ catalogId: String, context: ModelContext) -> Bool {
        findInstalledSkill(catalogId: catalogId, context: context) != nil
    }

    func isAgentInstalled(_ catalogId: String, context: ModelContext) -> Bool {
        findInstalledAgent(catalogId: catalogId, context: context) != nil
    }

    private func findInstalledMCP(catalogId: String, context: ModelContext) -> MCPServer? {
        let descriptor = FetchDescriptor<MCPServer>(predicate: #Predicate { $0.catalogId == catalogId })
        return try? context.fetch(descriptor).first
    }

    private func findInstalledSkill(catalogId: String, context: ModelContext) -> Skill? {
        let descriptor = FetchDescriptor<Skill>(predicate: #Predicate { $0.catalogId == catalogId })
        return try? context.fetch(descriptor).first
    }

    private func findInstalledAgent(catalogId: String, context: ModelContext) -> Agent? {
        let descriptor = FetchDescriptor<Agent>(predicate: #Predicate { $0.catalogId == catalogId })
        return try? context.fetch(descriptor).first
    }
}
