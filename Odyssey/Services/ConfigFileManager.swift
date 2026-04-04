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
    private static let bundledAgentSlugs = ["orchestrator", "coder", "reviewer", "researcher", "tester", "devops", "writer", "product-manager", "analyst", "designer", "config-agent"]
    private static let bundledSkillSlugs = ["peer-collaboration", "blackboard-patterns", "delegation-patterns", "workspace-collaboration", "agent-identity", "artifact-handoff-gate", "product-artifact-gate", "config-editing", "github-workflow"]
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
        let dirs = ["agents", "groups", "skills", "mcps", "permissions", "templates"]
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

    // MARK: - Slug Helpers

    /// Convert a display name to a kebab-case slug (e.g., "Product Manager" → "product-manager")
    static func slugify(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " + ", with: "-plus-")
            .replacingOccurrences(of: " & ", with: "-and-")
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
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
                defaultMission: "Perform a security audit of the codebase.",
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
}
