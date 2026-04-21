import CryptoKit
import Foundation
import OSLog

// MARK: - Config DTOs

/// Matches the JSON format of agent config files (same as DefaultAgents/*.json + enabled)
struct AgentConfigDTO: Codable {
    let name: String
    var enabled: Bool = true
    let agentDescription: String
    let provider: String
    let model: String
    let icon: String
    let color: String
    let skillNames: [String]
    let mcpServerNames: [String]
    let permissionSetName: String
    let systemPromptTemplate: String?
    let systemPromptVariables: [String: String]?
    let maxTurns: Int?
    let maxBudget: Double?
    let maxThinkingTokens: Int?
    let defaultWorkingDirectory: String?
    let instancePolicy: String?
    let instancePolicyPoolMax: Int?

    enum CodingKeys: String, CodingKey {
        case name, enabled, agentDescription, model, icon, color
        case provider
        case skillNames, mcpServerNames, permissionSetName
        case systemPromptTemplate, systemPromptVariables
        case maxTurns, maxBudget, maxThinkingTokens
        case defaultWorkingDirectory
        case instancePolicy, instancePolicyPoolMax
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        agentDescription = try c.decode(String.self, forKey: .agentDescription)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ProviderSelection.system.rawValue
        model = try c.decode(String.self, forKey: .model)
        icon = try c.decode(String.self, forKey: .icon)
        color = try c.decode(String.self, forKey: .color)
        skillNames = try c.decode([String].self, forKey: .skillNames)
        mcpServerNames = try c.decode([String].self, forKey: .mcpServerNames)
        permissionSetName = try c.decode(String.self, forKey: .permissionSetName)
        systemPromptTemplate = try c.decodeIfPresent(String.self, forKey: .systemPromptTemplate)
        systemPromptVariables = try c.decodeIfPresent([String: String].self, forKey: .systemPromptVariables)
        maxTurns = try c.decodeIfPresent(Int.self, forKey: .maxTurns)
        maxBudget = try c.decodeIfPresent(Double.self, forKey: .maxBudget)
        maxThinkingTokens = try c.decodeIfPresent(Int.self, forKey: .maxThinkingTokens)
        defaultWorkingDirectory = try c.decodeIfPresent(String.self, forKey: .defaultWorkingDirectory)
        instancePolicy = try c.decodeIfPresent(String.self, forKey: .instancePolicy)
        instancePolicyPoolMax = try c.decodeIfPresent(Int.self, forKey: .instancePolicyPoolMax)
    }

    init(
        name: String, enabled: Bool = true, agentDescription: String, provider: String = ProviderSelection.system.rawValue, model: String, icon: String, color: String,
        skillNames: [String], mcpServerNames: [String], permissionSetName: String,
        systemPromptTemplate: String?, systemPromptVariables: [String: String]?,
        maxTurns: Int?, maxBudget: Double?, maxThinkingTokens: Int?,
        defaultWorkingDirectory: String?, instancePolicy: String? = nil, instancePolicyPoolMax: Int? = nil
    ) {
        self.name = name
        self.enabled = enabled
        self.agentDescription = agentDescription
        self.provider = provider
        self.model = model
        self.icon = icon
        self.color = color
        self.skillNames = skillNames
        self.mcpServerNames = mcpServerNames
        self.permissionSetName = permissionSetName
        self.systemPromptTemplate = systemPromptTemplate
        self.systemPromptVariables = systemPromptVariables
        self.maxTurns = maxTurns
        self.maxBudget = maxBudget
        self.maxThinkingTokens = maxThinkingTokens
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.instancePolicy = instancePolicy
        self.instancePolicyPoolMax = instancePolicyPoolMax
    }
}

struct GroupConfigDTO: Codable {
    let name: String
    var enabled: Bool = true
    let description: String
    let icon: String
    let color: String
    let instruction: String
    let defaultMission: String?
    let agentNames: [String]
    let sortOrder: Int
    let autoReplyEnabled: Bool?
    let autonomousCapable: Bool?
    let coordinatorAgentName: String?
    let roles: [String: String]?
    let workflow: [WorkflowStepDTO]?

    enum CodingKeys: String, CodingKey {
        case name, enabled, description, icon, color, instruction, defaultMission
        case agentNames, sortOrder, autoReplyEnabled, autonomousCapable
        case coordinatorAgentName, roles, workflow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        description = try c.decode(String.self, forKey: .description)
        icon = try c.decode(String.self, forKey: .icon)
        color = try c.decode(String.self, forKey: .color)
        instruction = try c.decode(String.self, forKey: .instruction)
        defaultMission = try c.decodeIfPresent(String.self, forKey: .defaultMission)
        agentNames = try c.decode([String].self, forKey: .agentNames)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        autoReplyEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoReplyEnabled)
        autonomousCapable = try c.decodeIfPresent(Bool.self, forKey: .autonomousCapable)
        coordinatorAgentName = try c.decodeIfPresent(String.self, forKey: .coordinatorAgentName)
        roles = try c.decodeIfPresent([String: String].self, forKey: .roles)
        workflow = try c.decodeIfPresent([WorkflowStepDTO].self, forKey: .workflow)
    }

    init(
        name: String, enabled: Bool = true, description: String, icon: String, color: String,
        instruction: String, defaultMission: String?, agentNames: [String], sortOrder: Int,
        autoReplyEnabled: Bool?, autonomousCapable: Bool?, coordinatorAgentName: String?,
        roles: [String: String]?, workflow: [WorkflowStepDTO]?
    ) {
        self.name = name
        self.enabled = enabled
        self.description = description
        self.icon = icon
        self.color = color
        self.instruction = instruction
        self.defaultMission = defaultMission
        self.agentNames = agentNames
        self.sortOrder = sortOrder
        self.autoReplyEnabled = autoReplyEnabled
        self.autonomousCapable = autonomousCapable
        self.coordinatorAgentName = coordinatorAgentName
        self.roles = roles
        self.workflow = workflow
    }
}

struct WorkflowStepDTO: Codable {
    let agentName: String
    let instruction: String
    let label: String
    let autoAdvance: Bool
    let condition: String?
    let artifactGate: WorkflowArtifactGate?
}

struct MCPConfigDTO: Codable {
    let name: String
    var enabled: Bool = true
    let serverDescription: String
    let transportKind: String
    let transportCommand: String?
    let transportArgs: [String]?
    let transportEnv: [String: String]?
    let transportUrl: String?
    let transportHeaders: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name, enabled, serverDescription, transportKind
        case transportCommand, transportArgs, transportEnv
        case transportUrl, transportHeaders
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        serverDescription = try c.decode(String.self, forKey: .serverDescription)
        transportKind = try c.decode(String.self, forKey: .transportKind)
        transportCommand = try c.decodeIfPresent(String.self, forKey: .transportCommand)
        transportArgs = try c.decodeIfPresent([String].self, forKey: .transportArgs)
        transportEnv = try c.decodeIfPresent([String: String].self, forKey: .transportEnv)
        transportUrl = try c.decodeIfPresent(String.self, forKey: .transportUrl)
        transportHeaders = try c.decodeIfPresent([String: String].self, forKey: .transportHeaders)
    }

    init(
        name: String, enabled: Bool = true, serverDescription: String, transportKind: String,
        transportCommand: String?, transportArgs: [String]?, transportEnv: [String: String]?,
        transportUrl: String?, transportHeaders: [String: String]?
    ) {
        self.name = name
        self.enabled = enabled
        self.serverDescription = serverDescription
        self.transportKind = transportKind
        self.transportCommand = transportCommand
        self.transportArgs = transportArgs
        self.transportEnv = transportEnv
        self.transportUrl = transportUrl
        self.transportHeaders = transportHeaders
    }
}

struct PermissionConfigDTO: Codable {
    let name: String
    var enabled: Bool = true
    let allowRules: [String]
    let denyRules: [String]
    let additionalDirectories: [String]
    let permissionMode: String

    enum CodingKeys: String, CodingKey {
        case name, enabled, allowRules, denyRules, additionalDirectories, permissionMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        allowRules = try c.decode([String].self, forKey: .allowRules)
        denyRules = try c.decode([String].self, forKey: .denyRules)
        additionalDirectories = try c.decodeIfPresent([String].self, forKey: .additionalDirectories) ?? []
        permissionMode = try c.decodeIfPresent(String.self, forKey: .permissionMode) ?? "default"
    }

    init(name: String, enabled: Bool = true, allowRules: [String], denyRules: [String], additionalDirectories: [String], permissionMode: String) {
        self.name = name
        self.enabled = enabled
        self.allowRules = allowRules
        self.denyRules = denyRules
        self.additionalDirectories = additionalDirectories
        self.permissionMode = permissionMode
    }
}

struct SkillFrontmatterDTO {
    var name: String
    var description: String
    var category: String
    var enabled: Bool
    var triggers: [String]
    var version: String
    var mcpServerNames: [String]
    var content: String // full file content including frontmatter
}

/// A prompt template on disk: frontmatter metadata + body prompt.
struct PromptTemplateFileDTO {
    var name: String
    var sortOrder: Int
    var prompt: String
}

enum PromptTemplateOwnerKindOnDisk: String, CaseIterable {
    case agents
    case groups
    case projects
}

enum BuiltInConfigKind: String, CaseIterable {
    case agents
    case groups
    case skills
    case mcps
    case permissions
    case templates

    var label: String {
        switch self {
        case .agents: "agents"
        case .groups: "groups"
        case .skills: "skills"
        case .mcps: "MCPs"
        case .permissions: "permission presets"
        case .templates: "prompt templates"
        }
    }
}

struct BuiltInConfigDriftSummary {
    var itemsByKind: [BuiltInConfigKind: [String]]

    var isEmpty: Bool {
        itemsByKind.values.allSatisfy(\.isEmpty)
    }

    var totalItemCount: Int {
        itemsByKind.values.reduce(0) { $0 + $1.count }
    }

    var kindSummary: String {
        BuiltInConfigKind.allCases
            .compactMap { kind -> String? in
                guard let count = itemsByKind[kind]?.count, count > 0 else { return nil }
                return count == 1 ? "1 \(kind.label)" : "\(count) \(kind.label)"
            }
            .joined(separator: ", ")
    }

    func preview(limit: Int = 8) -> String {
        let names = BuiltInConfigKind.allCases
            .flatMap { kind in
                (itemsByKind[kind] ?? []).map { "\(kind.label): \($0)" }
            }
        guard names.count > limit else {
            return names.joined(separator: "\n")
        }
        let shown = names.prefix(limit).joined(separator: "\n")
        return shown + "\n…"
    }
}

// MARK: - ConfigFileManager

/// Pure file I/O for config directory. No SwiftData dependency.
enum ConfigFileManager {
    private static let bundledAgentSlugs = ["orchestrator", "coder", "reviewer", "researcher", "tester", "devops", "writer", "product-manager", "analyst", "designer", "config-agent", "friday", "performance", "ceo", "cto", "cmo", "cfo", "cpo"]
    private static let bundledSkillSlugs = ["peer-collaboration", "blackboard-patterns", "delegation-patterns", "workspace-collaboration", "agent-identity", "artifact-handoff-gate", "product-artifact-gate", "config-editing", "github-workflow", "task-board-patterns", "personal-context"]
    private static let bundledTemplateNames = ["specialist", "worker", "coordinator"]

    static var configDirectory: URL {
        let dataDir = ProcessInfo.processInfo.environment["ODYSSEY_DATA_DIR"]
            ?? ProcessInfo.processInfo.environment["CLAUDESTUDIO_DATA_DIR"]
            ?? "\(NSHomeDirectory())/.odyssey"
        return URL(fileURLWithPath: dataDir).appendingPathComponent("config")
    }

    static var factoryDirectory: URL {
        configDirectory.appendingPathComponent(".factory")
    }

    static func syncBundledBuiltIns(overwriteExisting: Bool) {
        do {
            try createDirectoryStructure()
            try syncBundledBuiltIns(into: factoryDirectory, overwriteExisting: true)
            try syncBundledBuiltIns(into: configDirectory, overwriteExisting: overwriteExisting)
        } catch {
            Log.configSync.error("Failed to sync bundled built-ins: \(error)")
        }
    }

    static func bundledBuiltInDriftSummary() -> BuiltInConfigDriftSummary {
        var itemsByKind: [BuiltInConfigKind: [String]] = [:]

        for kind in BuiltInConfigKind.allCases {
            itemsByKind[kind] = bundledItemNames(for: kind).filter { itemName in
                let targetFile = targetURL(for: kind, itemName: itemName, baseDirectory: configDirectory)
                guard FileManager.default.fileExists(atPath: targetFile.path) else { return false }
                guard let expectedData = try? bundledData(for: kind, itemName: itemName) else { return false }
                return currentData(at: targetFile) != expectedData
            }
        }

        return BuiltInConfigDriftSummary(itemsByKind: itemsByKind)
    }

    // MARK: - Directory Management

    static func directoryExists() -> Bool {
        FileManager.default.fileExists(atPath: configDirectory.path)
    }

    static func createDirectoryStructure() throws {
        let fm = FileManager.default
        let dirs = ["agents", "groups", "skills", "mcps", "permissions", "templates", "prompt-templates", "prompt-templates/agents", "prompt-templates/groups", "prompt-templates/projects"]
        for dir in dirs {
            try fm.createDirectory(at: configDirectory.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        // Factory reference directory
        for dir in dirs {
            try fm.createDirectory(at: factoryDirectory.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
    }

    // MARK: - Read All

    static func readAllAgents() -> [(slug: String, dto: AgentConfigDTO)] {
        readAllJSON(subdirectory: "agents")
    }

    static func readAllGroups() -> [(slug: String, dto: GroupConfigDTO)] {
        readAllJSON(subdirectory: "groups")
    }

    static func readAllMCPs() -> [(slug: String, dto: MCPConfigDTO)] {
        readAllJSON(subdirectory: "mcps")
    }

    static func readAllPermissions() -> [(slug: String, dto: PermissionConfigDTO)] {
        readAllJSON(subdirectory: "permissions")
    }

    static func readAllSkills() -> [(slug: String, dto: SkillFrontmatterDTO)] {
        let dir = configDirectory.appendingPathComponent("skills")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        var results: [(slug: String, dto: SkillFrontmatterDTO)] = []
        for subdir in contents where subdir.hasDirectoryPath {
            let skillFile = subdir.appendingPathComponent("SKILL.md")
            guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { continue }
            let slug = subdir.lastPathComponent
            let dto = parseSkillFrontmatter(content, fallbackName: slug)
            results.append((slug: slug, dto: dto))
        }
        return results
    }

    static func readAllTemplates() -> [String: String] {
        let dir = configDirectory.appendingPathComponent("templates")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [:] }

        var templates: [String: String] = [:]
        for file in contents where file.pathExtension == "md" {
            let name = file.deletingPathExtension().lastPathComponent
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                templates[name] = content
            }
        }
        return templates
    }

    // MARK: - Write

    static func writeAgent(_ dto: AgentConfigDTO, slug: String) throws {
        try writeJSON(dto, subdirectory: "agents", slug: slug)
    }

    static func writeGroup(_ dto: GroupConfigDTO, slug: String) throws {
        try writeJSON(dto, subdirectory: "groups", slug: slug)
    }

    static func writeMCP(_ dto: MCPConfigDTO, slug: String) throws {
        try writeJSON(dto, subdirectory: "mcps", slug: slug)
    }

    static func writePermission(_ dto: PermissionConfigDTO, slug: String) throws {
        try writeJSON(dto, subdirectory: "permissions", slug: slug)
    }

    static func writeSkill(_ dto: SkillFrontmatterDTO, slug: String) throws {
        let dir = configDirectory.appendingPathComponent("skills/\(slug)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("SKILL.md")
        try dto.content.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - Factory Defaults

    /// Copy factory defaults from the app bundle to both ~/.odyssey/config/ and .factory/
    static func copyFactoryDefaults() throws {
        try createDirectoryStructure()
        try syncBundledBuiltIns(into: configDirectory, overwriteExisting: true)
        try syncBundledBuiltIns(into: factoryDirectory, overwriteExisting: true)
        syncBundledPromptTemplates(overwriteExisting: true)
    }

    /// Restore a single entity's factory default
    static func restoreFactoryDefault(entityType: String, slug: String) -> Bool {
        let factoryFile: URL
        let targetFile: URL

        if entityType == "skills" {
            factoryFile = factoryDirectory.appendingPathComponent("\(entityType)/\(slug)/SKILL.md")
            targetFile = configDirectory.appendingPathComponent("\(entityType)/\(slug)/SKILL.md")
        } else {
            factoryFile = factoryDirectory.appendingPathComponent("\(entityType)/\(slug).json")
            targetFile = configDirectory.appendingPathComponent("\(entityType)/\(slug).json")
        }

        guard FileManager.default.fileExists(atPath: factoryFile.path) else { return false }

        do {
            if entityType == "skills" {
                let dir = configDirectory.appendingPathComponent("\(entityType)/\(slug)")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            if FileManager.default.fileExists(atPath: targetFile.path) {
                try FileManager.default.removeItem(at: targetFile)
            }
            try FileManager.default.copyItem(at: factoryFile, to: targetFile)
            return true
        } catch {
            Log.configFile.error("Failed to restore factory default \(entityType, privacy: .public)/\(slug, privacy: .public): \(error)")
            return false
        }
    }

    /// Restore all factory defaults for a given entity type
    static func restoreFactoryDefaults(entityType: String) throws {
        let factoryDir = factoryDirectory.appendingPathComponent(entityType)
        let targetDir = configDirectory.appendingPathComponent(entityType)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: factoryDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }

        for item in contents {
            let targetItem = targetDir.appendingPathComponent(item.lastPathComponent)
            if FileManager.default.fileExists(atPath: targetItem.path) {
                try FileManager.default.removeItem(at: targetItem)
            }
            try FileManager.default.copyItem(at: item, to: targetItem)
        }
    }

    /// Full factory reset: delete config dir contents, re-copy from bundle
    static func factoryReset() throws {
        let fm = FileManager.default
        // Remove all non-.factory contents
        if let contents = try? fm.contentsOfDirectory(
            at: configDirectory, includingPropertiesForKeys: nil, options: []
        ) {
            for item in contents {
                try fm.removeItem(at: item)
            }
        }
        try copyFactoryDefaults()
    }

    /// Check if a factory default exists for a given entity
    static func hasFactoryDefault(entityType: String, slug: String) -> Bool {
        let path: String
        if entityType == "skills" {
            path = factoryDirectory.appendingPathComponent("\(entityType)/\(slug)/SKILL.md").path
        } else {
            path = factoryDirectory.appendingPathComponent("\(entityType)/\(slug).json").path
        }
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - File-Backed Config Directories

    static var agentsDirectory: URL {
        configDirectory.appendingPathComponent("agents")
    }

    static var groupsDirectory: URL {
        configDirectory.appendingPathComponent("groups")
    }

    static var skillsDirectory: URL {
        configDirectory.appendingPathComponent("skills")
    }

    static var mcpsDirectory: URL {
        configDirectory.appendingPathComponent("mcps")
    }

    // MARK: - File-Backed Read Methods

    /// Read all file-backed agents from ~/.odyssey/config/agents/{slug}/.
    /// Returns tuples of (slug, config.json DTO, prompt.md content).
    /// Skips subdirectories missing config.json; logs and skips on parse errors.
    static func readAllAgentFiles() -> [(slug: String, config: AgentConfigFileDTO, prompt: String)] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: agentsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        var results: [(slug: String, config: AgentConfigFileDTO, prompt: String)] = []
        let decoder = JSONDecoder()
        for subdir in contents where (try? subdir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let slug = subdir.lastPathComponent
            let configFile = subdir.appendingPathComponent("config.json")
            guard fm.fileExists(atPath: configFile.path) else { continue }
            guard let data = try? Data(contentsOf: configFile),
                  let config = try? decoder.decode(AgentConfigFileDTO.self, from: data) else {
                Log.configFile.warning("Failed to parse agent config: \(slug, privacy: .public)")
                continue
            }
            let promptFile = subdir.appendingPathComponent("prompt.md")
            let prompt = (try? String(contentsOf: promptFile, encoding: .utf8)) ?? ""
            results.append((slug: slug, config: config, prompt: prompt))
        }
        return results
    }

    /// Read all file-backed groups from ~/.odyssey/config/groups/{slug}/.
    /// Returns tuples of (slug, config.json DTO, instruction.md, mission.md?, workflow.json?).
    /// Skips subdirectories missing config.json; logs and skips on parse errors.
    static func readAllGroupFiles() -> [(slug: String, config: GroupConfigFileDTO, instruction: String, mission: String?, workflow: [WorkflowStepFileDTO]?)] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: groupsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        var results: [(slug: String, config: GroupConfigFileDTO, instruction: String, mission: String?, workflow: [WorkflowStepFileDTO]?)] = []
        let decoder = JSONDecoder()
        for subdir in contents where (try? subdir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let slug = subdir.lastPathComponent
            let configFile = subdir.appendingPathComponent("config.json")
            guard fm.fileExists(atPath: configFile.path) else { continue }
            guard let data = try? Data(contentsOf: configFile),
                  let config = try? decoder.decode(GroupConfigFileDTO.self, from: data) else {
                Log.configFile.warning("Failed to parse group config: \(slug, privacy: .public)")
                continue
            }
            let instruction = (try? String(contentsOf: subdir.appendingPathComponent("instruction.md"), encoding: .utf8)) ?? ""
            let mission = try? String(contentsOf: subdir.appendingPathComponent("mission.md"), encoding: .utf8)
            var workflow: [WorkflowStepFileDTO]?
            let workflowFile = subdir.appendingPathComponent("workflow.json")
            if fm.fileExists(atPath: workflowFile.path),
               let wfData = try? Data(contentsOf: workflowFile),
               let wfSteps = try? decoder.decode([WorkflowStepFileDTO].self, from: wfData) {
                workflow = wfSteps
            }
            results.append((slug: slug, config: config, instruction: instruction, mission: mission, workflow: workflow))
        }
        return results
    }

    /// Read all file-backed skills from ~/.odyssey/config/skills/{slug}.md.
    /// Returns tuples of (slug, frontmatter DTO, markdown body).
    /// Logs and skips on parse errors.
    ///
    /// NOTE: This method uses the flat-file user-config layout ({slug}.md files directly
    /// inside the skills/ directory). The pre-existing readAllSkills() method uses a
    /// subdirectory layout ({slug}/SKILL.md). Both read from the same directory
    /// (~/.odyssey/config/skills/). Any pre-existing {slug}/SKILL.md subdirectory entries
    /// in that directory will be silently skipped by this method (they lack a .md extension
    /// at the top level).
    static func readAllSkillFiles() -> [(slug: String, dto: SkillFileDTO, content: String)] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: skillsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        var results: [(slug: String, dto: SkillFileDTO, content: String)] = []
        for file in contents where file.pathExtension == "md" {
            let slug = file.deletingPathExtension().lastPathComponent
            guard let raw = try? String(contentsOf: file, encoding: .utf8) else {
                Log.configFile.warning("Failed to read skill file: \(slug, privacy: .public)")
                continue
            }
            let (dto, body) = parseSkillFileFrontmatter(raw, fallbackSlug: slug)
            results.append((slug: slug, dto: dto, content: body))
        }
        return results
    }

    /// Read all file-backed MCP configs from ~/.odyssey/config/mcps/{slug}.json.
    /// Returns tuples of (slug, DTO). Logs and skips on parse errors.
    static func readAllMCPFiles() -> [(slug: String, dto: MCPConfigFileDTO)] {
        let dir = mcpsDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        let decoder = JSONDecoder()
        var results: [(slug: String, dto: MCPConfigFileDTO)] = []
        for file in contents where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let dto = try? decoder.decode(MCPConfigFileDTO.self, from: data) else {
                Log.configFile.warning("Failed to parse MCP file: \(file.lastPathComponent, privacy: .public)")
                continue
            }
            let slug = file.deletingPathExtension().lastPathComponent
            results.append((slug: slug, dto: dto))
        }
        return results
    }

    // MARK: - File-Backed Write Methods

    /// Write an agent config + prompt to ~/.odyssey/config/agents/{slug}/.
    static func writeBack(agentSlug: String, config: AgentConfigFileDTO, prompt: String) throws {
        let dir = agentsDirectory.appendingPathComponent(agentSlug)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        // NOTE: These writes are not transactional. If a later write fails after
        // an earlier one succeeds, the folder may be left in a partially-updated state.
        // ConfigSyncService will re-sync on next file-watch event.
        try data.write(to: dir.appendingPathComponent("config.json"), options: .atomic)
        try prompt.write(to: dir.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)
        gitCommit(message: "agent: update \(agentSlug)")
    }

    /// Write a group config, instruction, optional mission, and optional workflow to
    /// ~/.odyssey/config/groups/{slug}/.
    static func writeBack(groupSlug: String, config: GroupConfigFileDTO, instruction: String, mission: String?, workflow: [WorkflowStepFileDTO]?) throws {
        let dir = groupsDirectory.appendingPathComponent(groupSlug)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let configData = try encoder.encode(config)
        // NOTE: These writes are not transactional. If a later write fails after
        // an earlier one succeeds, the folder may be left in a partially-updated state.
        // ConfigSyncService will re-sync on next file-watch event.
        try configData.write(to: dir.appendingPathComponent("config.json"), options: .atomic)
        try instruction.write(to: dir.appendingPathComponent("instruction.md"), atomically: true, encoding: .utf8)
        if let mission {
            try mission.write(to: dir.appendingPathComponent("mission.md"), atomically: true, encoding: .utf8)
        }
        let workflowFile = dir.appendingPathComponent("workflow.json")
        if let workflow {
            let wfData = try encoder.encode(workflow)
            try wfData.write(to: workflowFile, options: .atomic)
        } else if fm.fileExists(atPath: workflowFile.path) {
            try fm.removeItem(at: workflowFile)
        }
        gitCommit(message: "group: update \(groupSlug)")
    }

    /// Write a skill (frontmatter + body) to ~/.odyssey/config/skills/{slug}.md.
    static func writeBack(skillSlug: String, dto: SkillFileDTO, content: String) throws {
        try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        let file = skillsDirectory.appendingPathComponent("\(skillSlug).md")
        let serialized = serializeSkillFile(dto, content: content)
        try serialized.write(to: file, atomically: true, encoding: .utf8)
        gitCommit(message: "skill: update \(skillSlug)")
    }

    /// Write an MCP config to ~/.odyssey/config/mcps/{slug}.json.
    static func writeBack(mcpSlug: String, dto: MCPConfigFileDTO) throws {
        try FileManager.default.createDirectory(at: mcpsDirectory, withIntermediateDirectories: true)
        let file = mcpsDirectory.appendingPathComponent("\(mcpSlug).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dto)
        try data.write(to: file, options: .atomic)
        gitCommit(message: "mcp: update \(mcpSlug)")
    }

    // MARK: - Bundled Catalog Sync

    /// Copy bundled Catalog/agents/ to ~/.odyssey/config/agents/ (skip slugs already present).
    static func syncBundledAgents() {
        // No bundled resources in Resources/Catalog/agents/ yet — no-op.
        // When catalog migration adds agent .json + .md pairs here, enumerate and copy.
    }

    /// Copy bundled Catalog/groups/ to ~/.odyssey/config/groups/ (skip slugs already present).
    static func syncBundledGroups() {
        // No bundled resources in Resources/Catalog/groups/ yet — no-op.
        // When catalog migration adds group directories here, enumerate and copy.
    }

    /// Copy bundled Catalog/skills/ to ~/.odyssey/config/skills/ (skip slugs already present).
    static func syncBundledSkills() throws {
        guard let root = bundledCatalogRoot(subdirectory: "skills") else {
            // No bundled catalog skills directory in app bundle yet — no-op.
            return
        }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        try fm.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        for file in files where file.pathExtension == "md" {
            let dest = skillsDirectory.appendingPathComponent(file.lastPathComponent)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            try fm.copyItem(at: file, to: dest)
        }
    }

    /// Copy bundled Catalog/mcps/ to ~/.odyssey/config/mcps/ (skip slugs already present).
    static func syncBundledMCPs() throws {
        guard let root = bundledCatalogRoot(subdirectory: "mcps") else {
            // No bundled catalog MCPs directory in app bundle yet — no-op.
            return
        }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        try fm.createDirectory(at: mcpsDirectory, withIntermediateDirectories: true)
        for file in files where file.pathExtension == "json" {
            let dest = mcpsDirectory.appendingPathComponent(file.lastPathComponent)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            try fm.copyItem(at: file, to: dest)
        }
    }

    // MARK: - SkillFileDTO Frontmatter Parsing

    /// Parse YAML frontmatter from a flat skills/{slug}.md file into a SkillFileDTO + body.
    private static func parseSkillFileFrontmatter(_ content: String, fallbackSlug: String) -> (SkillFileDTO, String) {
        var dto = SkillFileDTO(name: fallbackSlug, category: nil, triggers: nil)
        guard content.hasPrefix("---") else { return (dto, content) }

        // Split on first "---" that appears on its own line after the opening "---"
        let lines = content.components(separatedBy: "\n")
        var frontmatterLines: [String] = []
        var bodyLines: [String] = []
        var inFrontmatter = false
        var foundClosingDelimiter = false

        for line in lines {
            if !inFrontmatter && line.trimmingCharacters(in: .whitespaces) == "---" {
                inFrontmatter = true
                continue
            }
            if inFrontmatter && !foundClosingDelimiter {
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    foundClosingDelimiter = true
                    continue
                }
                frontmatterLines.append(line)
            } else if foundClosingDelimiter {
                bodyLines.append(line)
            }
        }

        guard foundClosingDelimiter else { return (dto, content) }

        let yaml = frontmatterLines.joined(separator: "\n")
        var body = bodyLines.joined(separator: "\n")
        // trim leading/trailing newlines from body
        body = body.trimmingCharacters(in: .newlines)

        var inTriggers = false

        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                dto.name = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                inTriggers = false
            } else if trimmed.hasPrefix("category:") {
                dto.category = trimmed.dropFirst(9).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                inTriggers = false
            } else if trimmed.hasPrefix("triggers:") {
                dto.triggers = []
                inTriggers = true
            } else if trimmed.hasPrefix("- ") && inTriggers {
                dto.triggers?.append(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("-") {
                inTriggers = false
            }
        }

        return (dto, body)
    }

    /// Serialize a SkillFileDTO + body back to a YAML-frontmatter markdown string.
    private static func serializeSkillFile(_ dto: SkillFileDTO, content: String) -> String {
        var yaml = "---\n"
        let escapedName = dto.name.replacingOccurrences(of: "\"", with: "\\\"")
        yaml += "name: \"\(escapedName)\"\n"
        if let category = dto.category, !category.isEmpty {
            yaml += "category: \(category)\n"
        }
        if let triggers = dto.triggers, !triggers.isEmpty {
            yaml += "triggers:\n"
            for trigger in triggers {
                yaml += "- \(trigger)\n"
            }
        }
        yaml += "---\n"
        return yaml + "\n" + content + "\n"
    }

    // MARK: - Private Catalog Bundle Helpers

    private static func bundledCatalogRoot(subdirectory: String) -> URL? {
        // App bundle first
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Catalog/\(subdirectory)"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Dev-mode fallbacks
        let candidates = [
            "\(NSHomeDirectory())/Odyssey/Odyssey/Resources/Catalog/\(subdirectory)",
            "\(FileManager.default.currentDirectoryPath)/Odyssey/Resources/Catalog/\(subdirectory)",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    // MARK: - Prompt Templates (per-owner markdown files)

    /// Root for user-editable chat-start prompt templates.
    /// Layout: `prompt-templates/{agents,groups,projects}/<owner-slug>/<template-slug>.md`.
    /// Kept distinct from `templates/` (which holds SystemPromptTemplates).
    static var promptTemplatesDirectory: URL {
        configDirectory.appendingPathComponent("prompt-templates")
    }

    static var promptTemplatesFactoryDirectory: URL {
        factoryDirectory.appendingPathComponent("prompt-templates")
    }

    /// Read every `.md` prompt template under `~/.odyssey/config/prompt-templates/`.
    /// Returns tuples of `(configSlug, ownerKind, ownerSlug, templateSlug, dto)` where
    /// `configSlug` matches the on-disk identity `agents/coder/review-pr`.
    static func readAllPromptTemplates() -> [(configSlug: String, ownerKind: PromptTemplateOwnerKindOnDisk, ownerSlug: String, templateSlug: String, dto: PromptTemplateFileDTO)] {
        var results: [(configSlug: String, ownerKind: PromptTemplateOwnerKindOnDisk, ownerSlug: String, templateSlug: String, dto: PromptTemplateFileDTO)] = []
        let fm = FileManager.default
        for ownerKind in PromptTemplateOwnerKindOnDisk.allCases {
            let kindDir = promptTemplatesDirectory.appendingPathComponent(ownerKind.rawValue)
            guard let ownerDirs = try? fm.contentsOfDirectory(
                at: kindDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }
            for ownerDir in ownerDirs where ownerDir.hasDirectoryPath {
                let ownerSlug = ownerDir.lastPathComponent
                guard let files = try? fm.contentsOfDirectory(
                    at: ownerDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
                ) else { continue }
                for file in files where file.pathExtension == "md" {
                    let templateSlug = file.deletingPathExtension().lastPathComponent
                    guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
                    let dto = parsePromptTemplateContent(content, fallbackName: templateSlug)
                    let configSlug = "\(ownerKind.rawValue)/\(ownerSlug)/\(templateSlug)"
                    results.append((configSlug: configSlug, ownerKind: ownerKind, ownerSlug: ownerSlug, templateSlug: templateSlug, dto: dto))
                }
            }
        }
        return results
    }

    /// List owner-slug folders that currently have prompt-template subdirectories.
    /// Used by the file watcher so per-owner folders are observed for edits.
    static func promptTemplateWatchDirectories() -> [URL] {
        let fm = FileManager.default
        var dirs: [URL] = [promptTemplatesDirectory]
        for ownerKind in PromptTemplateOwnerKindOnDisk.allCases.map(\.rawValue) {
            let kindDir = promptTemplatesDirectory.appendingPathComponent(ownerKind)
            dirs.append(kindDir)
            if let contents = try? fm.contentsOfDirectory(
                at: kindDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) {
                for entry in contents where entry.hasDirectoryPath {
                    dirs.append(entry)
                }
            }
        }
        return dirs
    }

    static func writePromptTemplate(
        ownerKind: PromptTemplateOwnerKindOnDisk,
        ownerSlug: String,
        templateSlug: String,
        dto: PromptTemplateFileDTO
    ) throws {
        let ownerDir = promptTemplatesDirectory
            .appendingPathComponent(ownerKind.rawValue)
            .appendingPathComponent(ownerSlug)
        try FileManager.default.createDirectory(at: ownerDir, withIntermediateDirectories: true)
        let file = ownerDir.appendingPathComponent("\(templateSlug).md")
        let serialized = serializePromptTemplate(dto)
        try serialized.write(to: file, atomically: true, encoding: .utf8)
    }

    static func deletePromptTemplate(
        ownerKind: PromptTemplateOwnerKindOnDisk,
        ownerSlug: String,
        templateSlug: String
    ) throws {
        let file = promptTemplatesDirectory
            .appendingPathComponent(ownerKind.rawValue)
            .appendingPathComponent(ownerSlug)
            .appendingPathComponent("\(templateSlug).md")
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return }
        try fm.removeItem(at: file)
    }

    /// Generate a fresh template slug under the given owner, suffixing `-2`, `-3`, …
    /// when the chosen slug already has a file on disk.
    static func uniquePromptTemplateSlug(
        baseName: String,
        ownerKind: PromptTemplateOwnerKindOnDisk,
        ownerSlug: String
    ) -> String {
        let base = slugify(baseName)
        let safeBase = base.isEmpty ? "template" : base
        let ownerDir = promptTemplatesDirectory
            .appendingPathComponent(ownerKind.rawValue)
            .appendingPathComponent(ownerSlug)
        let fm = FileManager.default

        var candidate = safeBase
        var suffix = 2
        while fm.fileExists(atPath: ownerDir.appendingPathComponent("\(candidate).md").path) {
            candidate = "\(safeBase)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// Copy bundled factory prompt-templates to `~/.odyssey/config/prompt-templates/` and
    /// the `.factory/` mirror. Only installs files missing at the destination unless
    /// `overwriteExisting` is true (for the "force refresh bundled defaults" path).
    static func syncBundledPromptTemplates(overwriteExisting: Bool) {
        let fm = FileManager.default
        let entries = bundledPromptTemplateEntries()

        for entry in entries {
            guard let data = loadBundlePromptTemplateContent(
                ownerKind: entry.ownerKind, ownerSlug: entry.ownerSlug, templateSlug: entry.templateSlug
            ) else {
                Log.configFile.warning("Missing bundled prompt template \(entry.configSlug, privacy: .public)")
                continue
            }
            let bytes = Data(data.utf8)

            // Always maintain a read-only mirror under .factory/
            let factoryTarget = promptTemplatesFactoryDirectory
                .appendingPathComponent(entry.ownerKind.rawValue)
                .appendingPathComponent(entry.ownerSlug)
                .appendingPathComponent("\(entry.templateSlug).md")
            try? writeBundledDataExposed(bytes, to: factoryTarget, overwriteExisting: true)

            // Install into the user-editable location only if missing (or forced).
            let liveTarget = promptTemplatesDirectory
                .appendingPathComponent(entry.ownerKind.rawValue)
                .appendingPathComponent(entry.ownerSlug)
                .appendingPathComponent("\(entry.templateSlug).md")
            if fm.fileExists(atPath: liveTarget.path) && !overwriteExisting {
                continue
            }
            try? writeBundledDataExposed(bytes, to: liveTarget, overwriteExisting: overwriteExisting)
        }
    }

    /// Snapshot of which bundled prompt-template files differ from the live copies.
    /// Mirrors `bundledBuiltInDriftSummary` but is returned as plain names.
    static func driftedPromptTemplates() -> [String] {
        var drift: [String] = []
        for entry in bundledPromptTemplateEntries() {
            let liveTarget = promptTemplatesDirectory
                .appendingPathComponent(entry.ownerKind.rawValue)
                .appendingPathComponent(entry.ownerSlug)
                .appendingPathComponent("\(entry.templateSlug).md")
            guard FileManager.default.fileExists(atPath: liveTarget.path) else { continue }
            guard let bundled = loadBundlePromptTemplateContent(
                ownerKind: entry.ownerKind, ownerSlug: entry.ownerSlug, templateSlug: entry.templateSlug
            ) else { continue }
            let current = (try? String(contentsOf: liveTarget, encoding: .utf8)) ?? ""
            if bundled != current {
                drift.append(entry.configSlug)
            }
        }
        return drift
    }

    // MARK: - Prompt Template Serialization

    static func parsePromptTemplateContent(_ content: String, fallbackName: String) -> PromptTemplateFileDTO {
        var dto = PromptTemplateFileDTO(name: fallbackName, sortOrder: 0, prompt: content)
        guard content.hasPrefix("---") else { return dto }
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else { return dto }
        let yaml = parts[1]
        let body = parts[2...].joined(separator: "---")

        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                let value = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                dto.name = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } else if trimmed.hasPrefix("sortOrder:") {
                let value = trimmed.dropFirst(10).trimmingCharacters(in: .whitespaces)
                dto.sortOrder = Int(value) ?? 0
            }
        }

        // Strip blank lines (whitespace-only) between `---` and the body, and any
        // trailing newline we always append when writing. Parsing → serializing
        // → parsing should be a fixed point.
        var prompt = body
        while let first = prompt.first, first.isNewline {
            prompt.removeFirst()
        }
        while let last = prompt.last, last.isNewline {
            prompt.removeLast()
        }
        dto.prompt = prompt
        return dto
    }

    static func serializePromptTemplate(_ dto: PromptTemplateFileDTO) -> String {
        let escapedName = dto.name.replacingOccurrences(of: "\"", with: "\\\"")
        let frontmatter = """
        ---
        name: "\(escapedName)"
        sortOrder: \(dto.sortOrder)
        ---

        """
        return frontmatter + dto.prompt + "\n"
    }

    // MARK: - Slug Helpers

    /// Convert a display name to a kebab-case slug (e.g., "Product Manager" → "product-manager")
    static func slugify(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " + ", with: "-plus-")
            .replacingOccurrences(of: " & ", with: "-and-")
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// Derive a stable disk slug for a project from its canonical root path.
    /// Uses the last path component, lowercased, with spaces replaced by dashes.
    /// E.g. "/Users/shay/Odyssey" → "odyssey", "My Project" → "my-project".
    static func projectSlug(for canonicalRootPath: String) -> String {
        let base = URL(fileURLWithPath: canonicalRootPath).lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let safeName = base.isEmpty ? "project" : base
        // Append a deterministic SHA256-based suffix to guarantee uniqueness when two projects share the same folder name.
        let digest = SHA256.hash(data: Data(canonicalRootPath.utf8))
        let hex = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
        return "\(safeName)-\(hex)"
    }

    // MARK: - Private Helpers

    private static func readAllJSON<T: Decodable>(subdirectory: String) -> [(slug: String, dto: T)] {
        let dir = configDirectory.appendingPathComponent(subdirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        let decoder = JSONDecoder()
        var results: [(slug: String, dto: T)] = []
        for file in contents where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let dto = try? decoder.decode(T.self, from: data) else {
                Log.configFile.warning("Failed to read \(file.lastPathComponent, privacy: .public)")
                continue
            }
            let slug = file.deletingPathExtension().lastPathComponent
            results.append((slug: slug, dto: dto))
        }
        return results
    }

    private static func writeJSON<T: Encodable>(_ dto: T, subdirectory: String, slug: String) throws {
        let dir = configDirectory.appendingPathComponent(subdirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(slug).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dto)
        try data.write(to: file)
    }

    // MARK: - Skill Frontmatter Parsing

    static func parseSkillFrontmatter(_ content: String, fallbackName: String) -> SkillFrontmatterDTO {
        var dto = SkillFrontmatterDTO(
            name: fallbackName, description: "", category: "General",
            enabled: true, triggers: [], version: "1.0", mcpServerNames: [], content: content
        )
        guard content.hasPrefix("---") else { return dto }
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else { return dto }
        let yaml = parts[1]
        var inTriggers = false
        var inMcps = false

        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                dto.name = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                inTriggers = false; inMcps = false
            } else if trimmed.hasPrefix("description:") {
                dto.description = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
                inTriggers = false; inMcps = false
            } else if trimmed.hasPrefix("category:") {
                dto.category = trimmed.dropFirst(9).trimmingCharacters(in: .whitespaces)
                inTriggers = false; inMcps = false
            } else if trimmed.hasPrefix("enabled:") {
                dto.enabled = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces) != "false"
                inTriggers = false; inMcps = false
            } else if trimmed.hasPrefix("version:") {
                dto.version = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                inTriggers = false; inMcps = false
            } else if trimmed.hasPrefix("triggers:") {
                inTriggers = true; inMcps = false
            } else if trimmed.hasPrefix("mcpServerNames:") {
                inMcps = true; inTriggers = false
            } else if trimmed.hasPrefix("- ") && inTriggers {
                dto.triggers.append(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("- ") && inMcps {
                dto.mcpServerNames.append(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("-") {
                inTriggers = false; inMcps = false
            }
        }
        return dto
    }

    private static func syncBundledBuiltIns(into baseDirectory: URL, overwriteExisting: Bool) throws {
        for kind in BuiltInConfigKind.allCases {
            for itemName in bundledItemNames(for: kind) {
                let targetFile = targetURL(for: kind, itemName: itemName, baseDirectory: baseDirectory)
                let expectedData = try bundledData(for: kind, itemName: itemName)
                try writeBundledData(expectedData, to: targetFile, overwriteExisting: overwriteExisting)
            }
        }
    }

    private static func bundledItemNames(for kind: BuiltInConfigKind) -> [String] {
        switch kind {
        case .agents:
            bundledAgentSlugs
        case .groups:
            builtInGroupDTOs().map(\.slug)
        case .skills:
            bundledSkillSlugs
        case .mcps:
            bundledMCPDTOs().map { slugify($0.name) }
        case .permissions:
            bundledPermissionDTOs().map { slugify($0.name) }
        case .templates:
            bundledTemplateNames
        }
    }

    private static func targetURL(for kind: BuiltInConfigKind, itemName: String, baseDirectory: URL) -> URL {
        switch kind {
        case .skills:
            baseDirectory.appendingPathComponent("skills/\(itemName)/SKILL.md")
        case .templates:
            baseDirectory.appendingPathComponent("templates/\(itemName).md")
        default:
            baseDirectory.appendingPathComponent("\(kind.rawValue)/\(itemName).json")
        }
    }

    private static func bundledData(for kind: BuiltInConfigKind, itemName: String) throws -> Data {
        switch kind {
        case .agents:
            guard let data = loadBundleResource(name: itemName, ext: "json", subdirectory: "DefaultAgents"),
                  var dto = try? JSONDecoder().decode(AgentConfigDTO.self, from: data) else {
                throw NSError(
                    domain: "ConfigFileManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing bundled agent \(itemName)"]
                )
            }
            dto.enabled = true
            return try encodedJSONData(dto)

        case .groups:
            guard let dto = builtInGroupDTOs().first(where: { $0.slug == itemName })?.dto else {
                throw NSError(
                    domain: "ConfigFileManager",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing bundled group \(itemName)"]
                )
            }
            var enabledDTO = dto
            enabledDTO.enabled = true
            return try encodedJSONData(enabledDTO)

        case .skills:
            guard let content = loadBundleSkillContent(name: itemName) else {
                throw NSError(
                    domain: "ConfigFileManager",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Missing bundled skill \(itemName)"]
                )
            }
            return Data(ensureEnabledInFrontmatter(content).utf8)

        case .mcps:
            guard let dto = bundledMCPDTOs().first(where: { slugify($0.name) == itemName }) else {
                throw NSError(
                    domain: "ConfigFileManager",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Missing bundled MCP \(itemName)"]
                )
            }
            var enabledDTO = dto
            enabledDTO.enabled = true
            return try encodedJSONData(enabledDTO)

        case .permissions:
            guard let dto = bundledPermissionDTOs().first(where: { slugify($0.name) == itemName }) else {
                throw NSError(
                    domain: "ConfigFileManager",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Missing bundled permission \(itemName)"]
                )
            }
            var enabledDTO = dto
            enabledDTO.enabled = true
            return try encodedJSONData(enabledDTO)

        case .templates:
            guard let content = loadBundleTemplateContent(name: itemName) else {
                throw NSError(
                    domain: "ConfigFileManager",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Missing bundled template \(itemName)"]
                )
            }
            return Data(content.utf8)
        }
    }

    private static func bundledMCPDTOs() -> [MCPConfigDTO] {
        guard let data = loadBundleResource(name: "DefaultMCPs", ext: "json"),
              let mcps = try? JSONDecoder().decode([MCPConfigDTO].self, from: data) else { return [] }
        return mcps
    }

    private static func bundledPermissionDTOs() -> [PermissionConfigDTO] {
        guard let data = loadBundleResource(name: "DefaultPermissionPresets", ext: "json"),
              let perms = try? JSONDecoder().decode([PermissionConfigDTO].self, from: data) else { return [] }
        return perms
    }

    private static func writeBundledData(_ data: Data, to targetFile: URL, overwriteExisting: Bool) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: targetFile.path) {
            guard overwriteExisting else { return }
            guard currentData(at: targetFile) != data else { return }
            try fm.removeItem(at: targetFile)
        }

        try fm.createDirectory(at: targetFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: targetFile, options: .atomic)
    }

    private static func currentData(at url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    private static func encodedJSONData<T: Encodable>(_ dto: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(dto)
    }

    // MARK: - Bundle Copy Helpers

    private static func copyBundleAgents() throws {
        try syncBundledBuiltIns(into: configDirectory, overwriteExisting: true)
    }

    private static func copyBundleMCPs() throws {
        try syncBundledBuiltIns(into: configDirectory, overwriteExisting: true)
    }

    private static func copyBundlePermissions() throws {
        try syncBundledBuiltIns(into: configDirectory, overwriteExisting: true)
    }

    private static func copyBundleSkills() throws {
        try syncBundledBuiltIns(into: configDirectory, overwriteExisting: true)
    }

    /// Ensure any new bundle skills that aren't yet in the config directory get copied.
    /// Called on every launch before performFullSync to handle incremental additions.
    static func ensureBundleSkillsPresent() {
        syncBundledBuiltIns(overwriteExisting: false)
    }

    /// Ensure any new bundled MCP configs that aren't yet in the config directory get copied.
    /// Called on every launch before performFullSync to handle incremental additions.
    static func ensureBundleMCPsPresent() {
        syncBundledBuiltIns(overwriteExisting: false)
    }

    /// Remove retired bundled MCP configs so stale defaults do not survive forever on existing installs.
    static func removeRetiredBundleMCPs(slugs: [String]) {
        let fm = FileManager.default

        for slug in slugs {
            let targetFile = configDirectory.appendingPathComponent("mcps/\(slug).json")
            guard fm.fileExists(atPath: targetFile.path) else { continue }

            do {
                try fm.removeItem(at: targetFile)
                Log.configSync.info("Removed retired bundle MCP config: \(slug, privacy: .public)")
            } catch {
                Log.configSync.error("Failed to remove retired bundle MCP config \(slug, privacy: .public): \(error)")
            }
        }
    }

    private static func copyBundleTemplates() throws {
        try syncBundledBuiltIns(into: configDirectory, overwriteExisting: true)
    }

    /// Create group JSON files from the built-in group definitions
    private static func createFactoryGroups() throws {
        let groups = builtInGroupDTOs()
        for (slug, dto) in groups {
            try writeJSON(dto, subdirectory: "groups", slug: slug)
        }
    }

    /// Copy current config to .factory/ reference directory
    private static func copyToFactory() throws {
        let fm = FileManager.default
        let subdirs = ["agents", "groups", "skills", "mcps", "permissions", "templates"]

        for subdir in subdirs {
            let source = configDirectory.appendingPathComponent(subdir)
            let target = factoryDirectory.appendingPathComponent(subdir)

            // Clear target
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.createDirectory(at: target, withIntermediateDirectories: true)

            guard let contents = try? fm.contentsOfDirectory(
                at: source, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }

            for item in contents {
                try fm.copyItem(at: item, to: target.appendingPathComponent(item.lastPathComponent))
            }
        }
    }

    private static func ensureEnabledInFrontmatter(_ content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else { return content }
        var yaml = parts[1]
        if !yaml.contains("enabled:") {
            yaml += "enabled: true\n"
        }
        return "---" + yaml + "---" + parts[2...].joined(separator: "---")
    }

    // MARK: - Built-in Group DTOs

    static func builtInGroupDTOs() -> [(slug: String, dto: GroupConfigDTO)] {
        return [
            ("dev-squad", GroupConfigDTO(
                name: "Dev Squad", description: "Core engineering trio for most coding tasks.",
                icon: "⚙️", color: "blue",
                instruction: "This is a software engineering group. Prioritize clean, tested, reviewed code. The Coder implements, the Reviewer critiques, the Tester validates.",
                defaultMission: nil, agentNames: ["Coder", "Reviewer", "Tester"], sortOrder: 0,
                autoReplyEnabled: true, autonomousCapable: false, coordinatorAgentName: nil, roles: nil,
                workflow: [
                    WorkflowStepDTO(agentName: "Coder", instruction: "Implement the requested changes. Write clean, well-structured code.", label: "Implement", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Reviewer", instruction: "Review the code from the previous step. Check for bugs, style issues, and architectural concerns. List any changes needed.", label: "Review", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Tester", instruction: "Write and run tests for the implementation. Verify the code works correctly and edge cases are covered.", label: "Test", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("code-review-pair", GroupConfigDTO(
                name: "Code Review Pair", description: "Fast pair review loop.",
                icon: "🔍", color: "green",
                instruction: "This is a focused code review session. Coder proposes changes, Reviewer provides actionable critique. Iterate until quality is met.",
                defaultMission: nil, agentNames: ["Coder", "Reviewer"], sortOrder: 1,
                autoReplyEnabled: true, autonomousCapable: false, coordinatorAgentName: nil, roles: nil,
                workflow: [
                    WorkflowStepDTO(agentName: "Coder", instruction: "Implement the requested changes or propose a solution.", label: "Code", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Reviewer", instruction: "Review the code critically. Approve if quality is met, or list specific changes needed.", label: "Review", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("full-stack-team", GroupConfigDTO(
                name: "Full Stack Team", description: "Complete engineering team with DevOps.",
                icon: "🏗️", color: "purple",
                instruction: "This is a full-stack engineering team. Coder builds, Reviewer ensures quality, Tester validates, DevOps handles infrastructure and deployment.",
                defaultMission: nil, agentNames: ["Coder", "Reviewer", "Tester", "DevOps"], sortOrder: 2,
                autoReplyEnabled: true, autonomousCapable: false, coordinatorAgentName: nil, roles: nil,
                workflow: [
                    WorkflowStepDTO(agentName: "Coder", instruction: "Implement the feature or fix.", label: "Implement", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Reviewer", instruction: "Review code quality, architecture, and correctness.", label: "Review", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Tester", instruction: "Write tests and validate the implementation. Present a signoff summary with risks and evidence before deployment continues.", label: "Test", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "test-signoff", approvalRequired: true, publishRepoDoc: false, blockedDownstreamAgentNames: ["DevOps"])),
                    WorkflowStepDTO(agentName: "DevOps", instruction: "Prepare deployment: update configs, CI/CD pipelines, and infrastructure as needed.", label: "Deploy", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("devops-pipeline", GroupConfigDTO(
                name: "DevOps Pipeline", description: "Build, test, deploy pipeline specialists.",
                icon: "🚀", color: "orange",
                instruction: "This group focuses on CI/CD and infrastructure. Coordinate to deliver reliable builds and deployments. Coder writes pipeline code, Tester validates, DevOps deploys.",
                defaultMission: nil, agentNames: ["Coder", "Tester", "DevOps"], sortOrder: 3,
                autoReplyEnabled: true, autonomousCapable: false, coordinatorAgentName: nil, roles: nil,
                workflow: [
                    WorkflowStepDTO(agentName: "Coder", instruction: "Write or update the pipeline code, scripts, or infrastructure config.", label: "Build", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Tester", instruction: "Validate the pipeline works correctly. Run smoke tests. Present a signoff summary before deployment continues.", label: "Validate", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "test-signoff", approvalRequired: true, publishRepoDoc: false, blockedDownstreamAgentNames: ["DevOps"])),
                    WorkflowStepDTO(agentName: "DevOps", instruction: "Deploy to the target environment. Verify health checks pass.", label: "Deploy", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("security-audit", GroupConfigDTO(
                name: "Security Audit", description: "Vulnerability analysis and hardening.",
                icon: "🔒", color: "red",
                instruction: "This group performs a security-focused review. Look for vulnerabilities, edge cases, and trust boundary violations. Coder identifies issues, Reviewer assesses risk, Tester writes exploit tests.",
                defaultMission: nil,
                agentNames: ["Coder", "Reviewer", "Tester"], sortOrder: 4,
                autoReplyEnabled: true, autonomousCapable: false, coordinatorAgentName: nil, roles: nil,
                workflow: [
                    WorkflowStepDTO(agentName: "Coder", instruction: "Scan the codebase for security vulnerabilities: injection, auth issues, data exposure, dependency risks. List all findings.", label: "Scan", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Reviewer", instruction: "Assess the severity and risk of each finding. Prioritize by impact. Recommend mitigations.", label: "Assess", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Tester", instruction: "Write proof-of-concept tests that demonstrate each vulnerability. Verify mitigations work.", label: "Exploit Tests", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("plan-and-build", GroupConfigDTO(
                name: "Plan & Build", description: "Orchestrated implementation with QA.",
                icon: "📋", color: "indigo",
                instruction: "Orchestrator plans and coordinates the work, Coder implements each task, Tester validates the output. Follow the plan step by step.",
                defaultMission: nil, agentNames: ["Orchestrator", "Coder", "Tester"], sortOrder: 5,
                autoReplyEnabled: true, autonomousCapable: true, coordinatorAgentName: "Orchestrator",
                roles: ["Orchestrator": "coordinator"],
                workflow: [
                    WorkflowStepDTO(agentName: "Orchestrator", instruction: "Break down the task into a step-by-step implementation plan. Present the plan in chat, persist it to the blackboard, and pause for explicit proceed before implementation begins.", label: "Plan", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "implementation-plan", approvalRequired: false, publishRepoDoc: false, blockedDownstreamAgentNames: ["Coder"])),
                    WorkflowStepDTO(agentName: "Coder", instruction: "Implement the plan from the previous step. Follow each step in order.", label: "Implement", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Tester", instruction: "Validate the implementation against the plan's acceptance criteria. Report pass/fail for each step.", label: "Validate", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("product-crew", GroupConfigDTO(
                name: "Product Crew", description: "Discovery, research, and strategy.",
                icon: "🎯", color: "teal",
                instruction: "This is a product strategy group. PM defines goals and requirements, Researcher gathers insights and competitive analysis, Analyst interprets data and tracks metrics.",
                defaultMission: nil, agentNames: ["Product Manager", "Researcher", "Analyst"], sortOrder: 6,
                autoReplyEnabled: true, autonomousCapable: false, coordinatorAgentName: nil,
                roles: ["Product Manager": "coordinator"],
                workflow: [
                    WorkflowStepDTO(agentName: "Researcher", instruction: "Research the topic: gather competitive insights, user needs, and market context.", label: "Research", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Analyst", instruction: "Analyze the research findings. Identify key metrics, trends, and data-driven insights.", label: "Analyze", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Product Manager", instruction: "Synthesize research and analysis into a product recommendation: goals, requirements, and success criteria.", label: "Recommend", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("pm-plus-dev", GroupConfigDTO(
                name: "PM + Dev", description: "Product planning to implementation.",
                icon: "🤝", color: "indigo",
                instruction: "PM defines requirements, Coder implements, Reviewer ensures quality, Tester validates the result. Bridge the gap between product vision and code.",
                defaultMission: nil, agentNames: ["Product Manager", "Coder", "Reviewer", "Tester"], sortOrder: 7,
                autoReplyEnabled: true, autonomousCapable: true, coordinatorAgentName: "Product Manager",
                roles: ["Product Manager": "coordinator"],
                workflow: [
                    WorkflowStepDTO(agentName: "Product Manager", instruction: "Gather requirements, present a PRD and low-fidelity wireframes in chat, persist the draft artifacts to the blackboard, ask for approval, and only after approval hand off implementation.", label: "Product Spec", autoAdvance: false, condition: nil, artifactGate: WorkflowArtifactGate(profile: "product-spec", approvalRequired: true, publishRepoDoc: true, blockedDownstreamAgentNames: ["Coder"])),
                    WorkflowStepDTO(agentName: "Coder", instruction: "Implement the requirements from the previous step.", label: "Implement", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Reviewer", instruction: "Review the implementation against the original requirements.", label: "Review", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Tester", instruction: "Test the implementation against the acceptance criteria. Report results.", label: "Test", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("content-studio", GroupConfigDTO(
                name: "Content Studio", description: "Research, write, and review content.",
                icon: "✍️", color: "blue",
                instruction: "This is a content production group. Researcher gathers information and sources, Writer drafts content, Reviewer polishes and fact-checks.",
                defaultMission: nil, agentNames: ["Researcher", "Writer", "Reviewer"], sortOrder: 8,
                autoReplyEnabled: true, autonomousCapable: false, coordinatorAgentName: nil, roles: nil,
                workflow: [
                    WorkflowStepDTO(agentName: "Researcher", instruction: "Research the topic thoroughly. Gather key facts, sources, and relevant context.", label: "Research", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Writer", instruction: "Draft the content using the research from the previous step. Write clearly and engagingly.", label: "Draft", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Reviewer", instruction: "Review the draft for accuracy, clarity, tone, and completeness. Suggest edits.", label: "Edit", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("growth-team", GroupConfigDTO(
                name: "Growth Team", description: "Data-driven growth and content.",
                icon: "📈", color: "green",
                instruction: "PM drives growth strategy, Analyst tracks metrics and identifies opportunities, Writer creates messaging and content. Focus on measurable growth outcomes.",
                defaultMission: nil, agentNames: ["Product Manager", "Analyst", "Writer"], sortOrder: 9,
                autoReplyEnabled: true, autonomousCapable: false, coordinatorAgentName: nil,
                roles: ["Product Manager": "coordinator"],
                workflow: [
                    WorkflowStepDTO(agentName: "Product Manager", instruction: "Define the growth objective and strategy. What metric are we moving and how?", label: "Strategy", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Analyst", instruction: "Analyze current metrics and identify the highest-impact opportunities for the strategy.", label: "Analysis", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Writer", instruction: "Create the messaging, copy, or content needed to execute the growth strategy.", label: "Content", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("design-review", GroupConfigDTO(
                name: "Design Review", description: "UX review with implementation awareness.",
                icon: "🎨", color: "pink",
                instruction: "Designer leads UX critique and evaluates usability, Coder evaluates implementation feasibility, Reviewer ensures consistency with existing patterns.",
                defaultMission: nil, agentNames: ["Designer", "Coder", "Reviewer"], sortOrder: 10,
                autoReplyEnabled: true, autonomousCapable: false, coordinatorAgentName: nil, roles: nil,
                workflow: [
                    WorkflowStepDTO(agentName: "Designer", instruction: "Evaluate the UX/UI. Present a concise UX spec with flows or wireframes in chat, persist it to the blackboard, and wait for approval before feasibility or implementation continues.", label: "UX Review", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "ux-spec", approvalRequired: true, publishRepoDoc: true, blockedDownstreamAgentNames: ["Coder"])),
                    WorkflowStepDTO(agentName: "Coder", instruction: "Assess feasibility of the design recommendations. Note implementation complexity and trade-offs.", label: "Feasibility", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Reviewer", instruction: "Review for consistency with existing design patterns and code conventions. Final recommendation.", label: "Consistency", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("full-ensemble", GroupConfigDTO(
                name: "Full Ensemble", description: "All ten agents working together.",
                icon: "🌐", color: "purple",
                instruction: "All agents are present. Collaborate, divide work by expertise, and coordinate via the blackboard. Each agent should contribute from their specialty.",
                defaultMission: nil,
                agentNames: ["Orchestrator", "Coder", "Reviewer", "Researcher", "Tester", "DevOps", "Writer", "Product Manager", "Analyst", "Designer"],
                sortOrder: 11,
                autoReplyEnabled: true, autonomousCapable: true, coordinatorAgentName: "Orchestrator",
                roles: ["Orchestrator": "coordinator"], workflow: nil
            )),
            ("security-perf-audit", GroupConfigDTO(
                name: "Security & Perf Audit", description: "Audit for security and performance issues, then fix them.",
                icon: "🔍", color: "red",
                instruction: "Reviewer audits for security vulnerabilities. Performance agent audits for bottlenecks. Orchestrator synthesizes findings into a prioritized fix plan. Coder implements the fixes.",
                defaultMission: nil,
                agentNames: ["Reviewer", "Performance", "Orchestrator", "Coder"],
                sortOrder: 12,
                autoReplyEnabled: true, autonomousCapable: true, coordinatorAgentName: "Orchestrator",
                roles: ["Orchestrator": "coordinator"],
                workflow: [
                    WorkflowStepDTO(agentName: "Reviewer", instruction: "Audit the codebase for security vulnerabilities: injection points, auth bypasses, data exposure, insecure defaults, and logical flaws. Write all findings to the blackboard under review.security.{component}. Mark critical findings as review.security.{component}.blocking = true.", label: "Security Audit", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Performance", instruction: "Audit the codebase for performance issues: algorithmic complexity, memory leaks, actor contention, SwiftUI rendering inefficiencies, and blocking I/O. Write all findings to the blackboard under perf.{component}.{finding}. Mark critical findings as perf.{component}.critical = true.", label: "Perf Audit", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "Orchestrator", instruction: "Read all security (review.security.*) and performance (perf.*) findings from the blackboard. Synthesize them into a prioritized fix plan ordered by severity and impact. Present the plan in chat, persist it to the blackboard under audit.fix-plan, and pause for explicit approval before Coder begins.", label: "Prioritize", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "audit-report", approvalRequired: true, publishRepoDoc: true, blockedDownstreamAgentNames: ["Coder"])),
                    WorkflowStepDTO(agentName: "Coder", instruction: "Implement the fixes from the audit fix plan. Address items in priority order. For each fix, note which finding it resolves.", label: "Fix", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
            ("lean-startup", GroupConfigDTO(
                name: "Lean Startup", description: "CEO-led executive team for strategy and cross-functional execution.",
                icon: "🏢", color: "indigo",
                instruction: "This is a startup executive team. CEO directs and synthesizes. CTO owns technology, CMO owns marketing and growth, CFO owns financial discipline, CPO owns product strategy. Each exec speaks from their domain — challenge each other constructively, then align on a clear decision or action plan.",
                defaultMission: nil, agentNames: ["CEO", "CTO", "CMO", "CFO", "CPO"], sortOrder: 17,
                autoReplyEnabled: true, autonomousCapable: true, coordinatorAgentName: "CEO",
                roles: ["CEO": "coordinator"],
                workflow: [
                    WorkflowStepDTO(agentName: "CEO", instruction: "Assess the request. Identify which domains it touches, frame the key questions for each exec, and kick off the discussion.", label: "Assess & Frame", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "CPO", instruction: "Define the product angle: what user problem are we solving, what should we build, and in what order?", label: "Product", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "CTO", instruction: "Assess technical feasibility: what can be built, how long will it take, and what are the architectural risks and trade-offs?", label: "Technology", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "CMO", instruction: "Define the go-to-market angle: how do we reach customers, what's the positioning, and which channels will we use?", label: "Marketing", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "CFO", instruction: "Model the financials: what does this cost, what's the ROI, what's the burn impact, and what's the downside scenario?", label: "Finance", autoAdvance: true, condition: nil, artifactGate: nil),
                    WorkflowStepDTO(agentName: "CEO", instruction: "Synthesize all exec inputs. Make the call: what do we do, in what order, and why? Produce a clear, actionable decision with owners and next steps.", label: "Decision", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            )),
        ]
    }

    // MARK: - Bundle Resource Loading (reused from DefaultsSeeder patterns)

    private static func loadBundleResource(name: String, ext: String, subdirectory: String? = nil) -> Data? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return try? Data(contentsOf: url)
        }
        // Folder references: Bundle.main.url(forResource:subdirectory:) doesn't search inside them
        if let resourceURL = Bundle.main.resourceURL {
            let path = subdirectory != nil ? "\(subdirectory!)/\(name).\(ext)" : "\(name).\(ext)"
            let url = resourceURL.appendingPathComponent(path)
            if let data = try? Data(contentsOf: url) {
                return data
            }
        }
        // Fallback for development
        let basePaths = [
            "\(NSHomeDirectory())/Odyssey/Odyssey/Resources",
            "\(FileManager.default.currentDirectoryPath)/Odyssey/Resources"
        ]
        for base in basePaths {
            let path = subdirectory != nil ? "\(base)/\(subdirectory!)/\(name).\(ext)" : "\(base)/\(name).\(ext)"
            if let data = FileManager.default.contents(atPath: path) {
                return data
            }
        }
        return nil
    }

    private static func loadBundleSkillContent(name: String) -> String? {
        if let url = Bundle.main.url(forResource: "SKILL", withExtension: "md", subdirectory: "DefaultSkills/\(name)") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("DefaultSkills/\(name)/SKILL.md")
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        let basePaths = [
            "\(NSHomeDirectory())/Odyssey/Odyssey/Resources/DefaultSkills/\(name)/SKILL.md",
            "\(FileManager.default.currentDirectoryPath)/Odyssey/Resources/DefaultSkills/\(name)/SKILL.md"
        ]
        for path in basePaths {
            if let content = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) {
                return content
            }
        }
        return nil
    }

    // MARK: - Bundled Prompt Templates

    /// Identity of a single bundled prompt template; used by factory sync + drift.
    struct BundledPromptTemplateEntry {
        var ownerKind: PromptTemplateOwnerKindOnDisk
        var ownerSlug: String
        var templateSlug: String
        var configSlug: String { "\(ownerKind.rawValue)/\(ownerSlug)/\(templateSlug)" }
    }

    /// Enumerate every bundled factory prompt-template `.md` under
    /// `Resources/DefaultPromptTemplates/{agents,groups}/<slug>/*.md`.
    static func bundledPromptTemplateEntries() -> [BundledPromptTemplateEntry] {
        guard let root = bundledPromptTemplatesRoot() else { return [] }
        var entries: [BundledPromptTemplateEntry] = []
        let fm = FileManager.default
        for ownerKind in [PromptTemplateOwnerKindOnDisk.agents, .groups] {
            let kindDir = root.appendingPathComponent(ownerKind.rawValue)
            guard let ownerDirs = try? fm.contentsOfDirectory(
                at: kindDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }
            for ownerDir in ownerDirs where ownerDir.hasDirectoryPath {
                guard let files = try? fm.contentsOfDirectory(
                    at: ownerDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
                ) else { continue }
                for file in files where file.pathExtension == "md" {
                    entries.append(BundledPromptTemplateEntry(
                        ownerKind: ownerKind,
                        ownerSlug: ownerDir.lastPathComponent,
                        templateSlug: file.deletingPathExtension().lastPathComponent
                    ))
                }
            }
        }
        return entries.sorted { lhs, rhs in
            if lhs.ownerKind != rhs.ownerKind { return lhs.ownerKind.rawValue < rhs.ownerKind.rawValue }
            if lhs.ownerSlug != rhs.ownerSlug { return lhs.ownerSlug < rhs.ownerSlug }
            return lhs.templateSlug < rhs.templateSlug
        }
    }

    static func loadBundlePromptTemplateContent(
        ownerKind: PromptTemplateOwnerKindOnDisk,
        ownerSlug: String,
        templateSlug: String
    ) -> String? {
        guard let root = bundledPromptTemplatesRoot() else { return nil }
        let url = root
            .appendingPathComponent(ownerKind.rawValue)
            .appendingPathComponent(ownerSlug)
            .appendingPathComponent("\(templateSlug).md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Public wrapper so new call sites can reuse the existing bundled-data writer.
    static func writeBundledDataExposed(_ data: Data, to targetFile: URL, overwriteExisting: Bool) throws {
        try writeBundledData(data, to: targetFile, overwriteExisting: overwriteExisting)
    }

    private static func bundledPromptTemplatesRoot() -> URL? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("DefaultPromptTemplates"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Dev-mode fallbacks so the feature works when running xcodebuild from source.
        let candidates = [
            "\(NSHomeDirectory())/Odyssey/Odyssey/Resources/DefaultPromptTemplates",
            "\(FileManager.default.currentDirectoryPath)/Odyssey/Resources/DefaultPromptTemplates",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func loadBundleTemplateContent(name: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "SystemPromptTemplates") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("SystemPromptTemplates/\(name).md")
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        let basePaths = [
            "\(NSHomeDirectory())/Odyssey/Odyssey/Resources/SystemPromptTemplates/\(name).md",
            "\(FileManager.default.currentDirectoryPath)/Odyssey/Resources/SystemPromptTemplates/\(name).md"
        ]
        for path in basePaths {
            if let content = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) {
                return content
            }
        }
        return nil
    }

    // MARK: - Git Backing

    /// Initialise a git repo in the config directory on first run.
    /// Idempotent — does nothing if `.git` already exists.
    static func ensureGitRepo() {
        let dir = configDirectory.path
        guard !FileManager.default.fileExists(atPath: "\(dir)/.git") else { return }

        @discardableResult func sh(_ args: String...) -> Bool {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = args
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        }

        sh("git", "-C", dir, "init", "-b", "main")
        let gitignore = "\(dir)/.gitignore"
        try? "/.factory\n/.DS_Store\n".write(toFile: gitignore, atomically: true, encoding: .utf8)
        sh("git", "-C", dir, "add", ".gitignore")
        sh("git", "-C", dir, "commit", "--allow-empty", "-m", "init: odyssey config repo")
    }

    /// Copy the bundled whats-new.json to ~/.odyssey/whats-new.json so Ulysses can read it.
    /// Always overwrites — the bundle is the source of truth.
    static func exportWhatsNew() {
        guard let src = Bundle.main.resourceURL?.appendingPathComponent("WhatsNew/whats-new.json"),
              FileManager.default.fileExists(atPath: src.path) else { return }
        let dest = configDirectory.deletingLastPathComponent().appendingPathComponent("whats-new.json")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: src, to: dest)
    }

    /// Stage all changes and commit with the given message. Best-effort — never throws.
    static func gitCommit(message: String) {
        let dir = configDirectory.path

        @discardableResult func sh(_ args: String...) -> Bool {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = args
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        }

        sh("git", "-C", dir, "add", "-A")
        sh("git", "-C", dir, "commit", "-m", message)
    }
}
