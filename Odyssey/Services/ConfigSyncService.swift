import AppKit
import Foundation
import OSLog
import SwiftData

/// Watches ~/.odyssey/config/ for changes and syncs to SwiftData.
/// Also provides write-back from SwiftData to files (bidirectional sync).
@MainActor
@Observable
final class ConfigSyncService {
    struct BuiltInMCPTransportSpec: Equatable {
        let command: String
        let args: [String]
        let env: [String: String]
    }

    private static let builtInAgentDefaultMCPNames: [String: [String]] = [
        "coder": ["Argus", "AppXray", "Octocode"],
        "tester": ["Argus", "AppXray", "Octocode"],
        "reviewer": ["Octocode"],
        "devops": [],
    ]
    private static let removedBuiltInAgentMCPNames: [String: Set<String>] = [
        "reviewer": ["GitHub"],
        "devops": ["GitHub"],
    ]
    private static let retiredBuiltInMCPSlugs: [String] = ["github"]

    static func builtInTransportSpec(for slug: String, existingEnv: [String: String] = [:]) -> BuiltInMCPTransportSpec? {
        switch slug {
        case "argus":
            if let localEntry = firstExistingBuiltInMCPEntryPath([
                "argus/packages/argus/dist/mcp/index.js",
                "wix-argus/packages/argus/dist/mcp/index.js",
            ]) {
                return BuiltInMCPTransportSpec(command: "node", args: [localEntry], env: existingEnv)
            }

            return BuiltInMCPTransportSpec(
                command: "npx",
                args: ["-y", "-p", "@wix/argus", "argus-mcp"],
                env: existingEnv
            )

        case "appxray":
            var env = existingEnv
            env["APPXRAY_AUTO_CONNECT"] = "true"

            if let localEntry = firstExistingBuiltInMCPEntryPath([
                "wix-appxray/appxray/packages/mcp-server/dist/index.js",
                "appxray/packages/mcp-server/dist/index.js",
            ]) {
                return BuiltInMCPTransportSpec(command: "node", args: [localEntry], env: env)
            }

            return BuiltInMCPTransportSpec(
                command: "npx",
                args: ["-y", "@wix/appxray-mcp-server"],
                env: env
            )

        default:
            return nil
        }
    }

    private static func firstExistingBuiltInMCPEntryPath(_ relativePaths: [String]) -> String? {
        let home = NSHomeDirectory()

        for relativePath in relativePaths {
            let candidate = URL(fileURLWithPath: home).appendingPathComponent(relativePath).path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private(set) var isWatching = false
    private var fileDescriptors: [Int32] = []
    private var dispatchSources: [DispatchSourceFileSystemObject] = []
    private let debounceQueue = DispatchQueue(label: "com.odyssey.config-sync.debounce")
    private var debounceWorkItem: DispatchWorkItem?
    private var isWritingBack = false // prevents feedback loop during UI write-back

    private var modelContainer: ModelContainer?
    var builtInOverridePolicyOverride: BuiltInConfigOverridePolicy?
    var builtInOverridePromptHandler: ((BuiltInConfigDriftSummary) -> Bool)?

    // MARK: - Lifecycle

    func start(container: ModelContainer) {
        self.modelContainer = container

        let needsMigration = !ConfigFileManager.directoryExists()

        if needsMigration {
            let context = ModelContext(container)
            let entityCount = (try? context.fetchCount(FetchDescriptor<Agent>())) ?? 0

            if entityCount > 0 {
                // Existing user: export SwiftData → files, then sync
                Log.configSync.info("Migrating existing data to config files")
                exportCurrentState(context: context)
            } else {
                // Fresh install: copy factory defaults
                Log.configSync.info("Fresh install — copying factory defaults")
                do {
                    try ConfigFileManager.copyFactoryDefaults()
                } catch {
                    Log.configSync.error("Failed to copy factory defaults: \(error)")
                }
            }
        }

        // Refresh bundled defaults according to the user's built-in override policy.
        applyBundledBuiltInSyncPolicy()

        // Full sync to pick up any offline edits or new factory defaults
        performFullSync()

        // Start watching
        startFileWatcher()
    }

    func stop() {
        stopFileWatcher()
        modelContainer = nil
    }

    // MARK: - Full Sync (files → SwiftData)

    private func applyBundledBuiltInSyncPolicy() {
        let policy = builtInOverridePolicyOverride
            ?? BuiltInConfigOverridePolicy(
                rawValue: AppSettings.store.string(forKey: AppSettings.builtInConfigOverridePolicyKey)
                    ?? AppSettings.defaultBuiltInConfigOverridePolicy
            )
            ?? .yes
        let driftSummary = ConfigFileManager.bundledBuiltInDriftSummary()

        let overwriteExisting: Bool
        switch policy {
        case .yes:
            overwriteExisting = true
        case .no:
            overwriteExisting = false
        case .ask:
            overwriteExisting = !driftSummary.isEmpty && shouldOverwriteBuiltInsAfterPrompt(driftSummary)
        }

        ConfigFileManager.syncBundledBuiltIns(overwriteExisting: overwriteExisting)

        if overwriteExisting {
            ConfigFileManager.removeRetiredBundleMCPs(slugs: Self.retiredBuiltInMCPSlugs)
        }
    }

    private func shouldOverwriteBuiltInsAfterPrompt(_ driftSummary: BuiltInConfigDriftSummary) -> Bool {
        if let builtInOverridePromptHandler {
            return builtInOverridePromptHandler(driftSummary)
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update Odyssey built-in configs from the app bundle?"

        let preview = driftSummary.preview()
        let previewSuffix = preview.isEmpty ? "" : "\n\nChanged items:\n\(preview)"
        alert.informativeText = """
        Your local built-in config files differ from the versions bundled with this app (\(driftSummary.kindSummary)).

        Choose “Update Built-Ins” to replace the local bundled copies. Choose “Keep Local Copies” to leave your current files as-is for this launch. You can change the default behavior in Settings > Developer.
        \(previewSuffix)
        """
        alert.addButton(withTitle: "Update Built-Ins")
        alert.addButton(withTitle: "Keep Local Copies")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func performFullSync() {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)

        Log.configSync.info("Starting full sync")

        // Load templates for system prompt resolution
        let templates = ConfigFileManager.readAllTemplates()

        // Sync each entity type
        syncPermissions(context: context)
        syncMCPs(context: context)
        syncSkills(context: context)
        syncAgents(context: context, templates: templates)
        syncGroups(context: context)

        do {
            try context.save()
            Log.configSync.info("Full sync complete")
        } catch {
            Log.configSync.error("Failed to save: \(error)")
        }
    }

    // MARK: - Entity Sync Methods

    private func syncPermissions(context: ModelContext) {
        let fileDTOs = ConfigFileManager.readAllPermissions()
        let existing = (try? context.fetch(FetchDescriptor<PermissionSet>())) ?? []
        let slugMap = Dictionary(uniqueKeysWithValues: existing.compactMap { e in
            e.configSlug.map { ($0, e) }
        })
        var seenSlugs: Set<String> = []

        for (slug, dto) in fileDTOs {
            seenSlugs.insert(slug)
            if let entity = slugMap[slug] {
                // Update existing
                entity.name = dto.name
                entity.allowRules = dto.allowRules
                entity.denyRules = dto.denyRules
                entity.additionalDirectories = dto.additionalDirectories
                entity.permissionMode = dto.permissionMode
                entity.isEnabled = dto.enabled
            } else {
                // Check by name (for migration)
                let byName = existing.first { $0.name == dto.name && $0.configSlug == nil }
                if let entity = byName {
                    entity.configSlug = slug
                    entity.allowRules = dto.allowRules
                    entity.denyRules = dto.denyRules
                    entity.additionalDirectories = dto.additionalDirectories
                    entity.permissionMode = dto.permissionMode
                    entity.isEnabled = dto.enabled
                } else {
                    // Insert new
                    let entity = PermissionSet(
                        name: dto.name, allowRules: dto.allowRules,
                        denyRules: dto.denyRules, permissionMode: dto.permissionMode
                    )
                    entity.additionalDirectories = dto.additionalDirectories
                    entity.isEnabled = dto.enabled
                    entity.configSlug = slug
                    context.insert(entity)
                }
            }
        }

        // Soft-disable entities whose files were removed
        for entity in existing where entity.configSlug != nil && !seenSlugs.contains(entity.configSlug!) {
            entity.isEnabled = false
        }
    }

    private func syncMCPs(context: ModelContext) {
        let fileDTOs = ConfigFileManager.readAllMCPs()
        let existing = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
        let slugMap = Dictionary(uniqueKeysWithValues: existing.compactMap { e in
            e.configSlug.map { ($0, e) }
        })
        var seenSlugs: Set<String> = []

        for (slug, dto) in fileDTOs {
            seenSlugs.insert(slug)
            let effectiveDTO = migrateBuiltInMCPIfNeeded(dto, slug: slug)
            if let entity = slugMap[slug] {
                entity.name = effectiveDTO.name
                entity.serverDescription = effectiveDTO.serverDescription
                entity.isEnabled = effectiveDTO.enabled
                applyTransport(dto: effectiveDTO, to: entity)
            } else {
                let byName = existing.first { $0.name == effectiveDTO.name && $0.configSlug == nil }
                if let entity = byName {
                    entity.configSlug = slug
                    entity.serverDescription = effectiveDTO.serverDescription
                    entity.isEnabled = effectiveDTO.enabled
                    applyTransport(dto: effectiveDTO, to: entity)
                } else {
                    let transport = makeTransport(from: effectiveDTO)
                    let entity = MCPServer(name: effectiveDTO.name, serverDescription: effectiveDTO.serverDescription, transport: transport)
                    entity.isEnabled = effectiveDTO.enabled
                    entity.configSlug = slug
                    context.insert(entity)
                }
            }
        }

        for entity in existing where entity.configSlug != nil && !seenSlugs.contains(entity.configSlug!) {
            entity.isEnabled = false
        }
    }

    private func syncSkills(context: ModelContext) {
        let fileDTOs = ConfigFileManager.readAllSkills()
        let existing = (try? context.fetch(FetchDescriptor<Skill>())) ?? []
        let slugMap = Dictionary(uniqueKeysWithValues: existing.compactMap { e in
            e.configSlug.map { ($0, e) }
        })
        var seenSlugs: Set<String> = []

        for (slug, dto) in fileDTOs {
            seenSlugs.insert(slug)
            if let entity = slugMap[slug] {
                entity.name = dto.name
                entity.skillDescription = dto.description
                entity.category = dto.category
                entity.content = dto.content
                entity.triggers = dto.triggers
                entity.version = dto.version
                entity.isEnabled = dto.enabled
            } else {
                let byName = existing.first { $0.name == dto.name && $0.configSlug == nil }
                if let entity = byName {
                    entity.configSlug = slug
                    entity.skillDescription = dto.description
                    entity.category = dto.category
                    entity.content = dto.content
                    entity.triggers = dto.triggers
                    entity.version = dto.version
                    entity.isEnabled = dto.enabled
                } else {
                    let entity = Skill(name: dto.name, skillDescription: dto.description, category: dto.category, content: dto.content)
                    entity.triggers = dto.triggers
                    entity.version = dto.version
                    entity.isEnabled = dto.enabled
                    entity.configSlug = slug
                    entity.source = .builtin
                    context.insert(entity)
                }
            }
        }

        for entity in existing where entity.configSlug != nil && !seenSlugs.contains(entity.configSlug!) {
            entity.isEnabled = false
        }
    }

    private func syncAgents(context: ModelContext, templates: [String: String]) {
        let fileDTOs = ConfigFileManager.readAllAgents()
        let existing = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let slugMap = Dictionary(uniqueKeysWithValues: existing.compactMap { e in
            e.configSlug.map { ($0, e) }
        })
        var seenSlugs: Set<String> = []

        // Build name → UUID maps for reference resolution
        let allSkills = (try? context.fetch(FetchDescriptor<Skill>())) ?? []
        let skillByName: [String: UUID] = Dictionary(uniqueKeysWithValues: allSkills.map { ($0.name, $0.id) })
        let allMCPs = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
        let mcpByName: [String: UUID] = Dictionary(uniqueKeysWithValues: allMCPs.map { ($0.name, $0.id) })
        let allPerms = (try? context.fetch(FetchDescriptor<PermissionSet>())) ?? []
        let permByName: [String: UUID] = Dictionary(uniqueKeysWithValues: allPerms.map { ($0.name, $0.id) })

        for (slug, dto) in fileDTOs {
            seenSlugs.insert(slug)
            let effectiveDTO = migrateBuiltInAgentMCPDefaultsIfNeeded(dto, slug: slug)
            let systemPrompt = resolveSystemPrompt(dto: effectiveDTO, templates: templates)
            let skillIds = effectiveDTO.skillNames.compactMap { skillByName[$0] }
            let mcpIds = effectiveDTO.mcpServerNames.compactMap { mcpByName[$0] }
            let permId = permByName[effectiveDTO.permissionSetName]

            if let entity = slugMap[slug] {
                entity.name = effectiveDTO.name
                entity.agentDescription = effectiveDTO.agentDescription
                entity.systemPrompt = systemPrompt
                entity.provider = effectiveDTO.provider
                entity.model = effectiveDTO.model
                entity.icon = effectiveDTO.icon
                entity.color = effectiveDTO.color
                entity.skillIds = skillIds
                entity.extraMCPServerIds = mcpIds
                entity.permissionSetId = permId
                entity.maxTurns = effectiveDTO.maxTurns
                entity.maxBudget = effectiveDTO.maxBudget
                entity.maxThinkingTokens = effectiveDTO.maxThinkingTokens
                entity.defaultWorkingDirectory = effectiveDTO.defaultWorkingDirectory
                entity.instancePolicy = AgentInstancePolicy(rawValue: effectiveDTO.instancePolicy ?? "") ?? .agentDefault
                entity.instancePolicyPoolMax = effectiveDTO.instancePolicyPoolMax
                entity.isEnabled = effectiveDTO.enabled
            } else {
                let byName = existing.first { $0.name == effectiveDTO.name && $0.configSlug == nil }
                if let entity = byName {
                    entity.configSlug = slug
                    entity.agentDescription = effectiveDTO.agentDescription
                    entity.systemPrompt = systemPrompt
                    entity.provider = effectiveDTO.provider
                    entity.model = effectiveDTO.model
                    entity.icon = effectiveDTO.icon
                    entity.color = effectiveDTO.color
                    entity.skillIds = skillIds
                    entity.extraMCPServerIds = mcpIds
                    entity.permissionSetId = permId
                    entity.maxTurns = effectiveDTO.maxTurns
                    entity.maxBudget = effectiveDTO.maxBudget
                    entity.maxThinkingTokens = effectiveDTO.maxThinkingTokens
                    entity.defaultWorkingDirectory = effectiveDTO.defaultWorkingDirectory
                    entity.instancePolicy = AgentInstancePolicy(rawValue: effectiveDTO.instancePolicy ?? "") ?? .agentDefault
                    entity.instancePolicyPoolMax = effectiveDTO.instancePolicyPoolMax
                    entity.isEnabled = effectiveDTO.enabled
                } else {
                    let entity = Agent(name: effectiveDTO.name, agentDescription: effectiveDTO.agentDescription, systemPrompt: systemPrompt, provider: effectiveDTO.provider, model: effectiveDTO.model, icon: effectiveDTO.icon, color: effectiveDTO.color)
                    entity.skillIds = skillIds
                    entity.extraMCPServerIds = mcpIds
                    entity.permissionSetId = permId
                    entity.maxTurns = effectiveDTO.maxTurns
                    entity.maxBudget = effectiveDTO.maxBudget
                    entity.maxThinkingTokens = effectiveDTO.maxThinkingTokens
                    entity.defaultWorkingDirectory = effectiveDTO.defaultWorkingDirectory
                    entity.instancePolicy = AgentInstancePolicy(rawValue: effectiveDTO.instancePolicy ?? "") ?? .agentDefault
                    entity.instancePolicyPoolMax = effectiveDTO.instancePolicyPoolMax
                    entity.isEnabled = effectiveDTO.enabled
                    entity.configSlug = slug
                    entity.origin = .builtin
                    context.insert(entity)
                }
            }
        }

        for entity in existing where entity.configSlug != nil && !seenSlugs.contains(entity.configSlug!) {
            entity.isEnabled = false
        }
    }

    private func migrateBuiltInMCPIfNeeded(_ dto: MCPConfigDTO, slug: String) -> MCPConfigDTO {
        let migrated: MCPConfigDTO

        switch slug {
        case "argus", "appxray":
            guard let transport = Self.builtInTransportSpec(for: slug, existingEnv: dto.transportEnv ?? [:]) else {
                return dto
            }

            migrated = MCPConfigDTO(
                name: dto.name,
                enabled: dto.enabled,
                serverDescription: dto.serverDescription,
                transportKind: "stdio",
                transportCommand: transport.command,
                transportArgs: transport.args,
                transportEnv: transport.env,
                transportUrl: nil,
                transportHeaders: nil
            )
        default:
            return dto
        }

        let changed = migrated.transportKind != dto.transportKind
            || migrated.transportCommand != dto.transportCommand
            || migrated.transportArgs != dto.transportArgs
            || migrated.transportEnv != dto.transportEnv
            || migrated.transportUrl != dto.transportUrl
            || migrated.transportHeaders != dto.transportHeaders

        guard changed else { return dto }

        do {
            try ConfigFileManager.writeMCP(migrated, slug: slug)
            Log.configSync.info("Migrated built-in MCP transport for \(slug, privacy: .public)")
        } catch {
            Log.configSync.error("Failed to migrate built-in MCP transport for \(slug, privacy: .public): \(error)")
        }

        return migrated
    }

    private func migrateBuiltInAgentMCPDefaultsIfNeeded(_ dto: AgentConfigDTO, slug: String) -> AgentConfigDTO {
        let builtInMCPNames = Self.builtInAgentDefaultMCPNames[slug] ?? []
        let retiredNames = Self.removedBuiltInAgentMCPNames[slug] ?? []

        var mergedMCPNames = dto.mcpServerNames.filter { !retiredNames.contains($0) }
        let removedMCPs = dto.mcpServerNames.filter { retiredNames.contains($0) }

        guard Self.builtInAgentDefaultMCPNames.keys.contains(slug) else {
            return dto
        }

        for name in builtInMCPNames where !mergedMCPNames.contains(name) {
            mergedMCPNames.append(name)
        }

        guard mergedMCPNames != dto.mcpServerNames else {
            return dto
        }

        let migrated = AgentConfigDTO(
            name: dto.name,
            enabled: dto.enabled,
            agentDescription: dto.agentDescription,
            provider: dto.provider,
            model: dto.model,
            icon: dto.icon,
            color: dto.color,
            skillNames: dto.skillNames,
            mcpServerNames: mergedMCPNames,
            permissionSetName: dto.permissionSetName,
            systemPromptTemplate: dto.systemPromptTemplate,
            systemPromptVariables: dto.systemPromptVariables,
            maxTurns: dto.maxTurns,
            maxBudget: dto.maxBudget,
            maxThinkingTokens: dto.maxThinkingTokens,
            defaultWorkingDirectory: dto.defaultWorkingDirectory,
            instancePolicy: dto.instancePolicy,
            instancePolicyPoolMax: dto.instancePolicyPoolMax
        )

        do {
            try ConfigFileManager.writeAgent(migrated, slug: slug)
            let addedMCPs = builtInMCPNames.filter { !dto.mcpServerNames.contains($0) }.joined(separator: ",")
            let removedBuiltIns = removedMCPs.joined(separator: ",")
            let finalMCPs = mergedMCPNames.joined(separator: ",")
            Log.configSync.info("Migrated built-in agent MCP defaults for \(slug, privacy: .public) (added: \(addedMCPs, privacy: .public); removed: \(removedBuiltIns, privacy: .public); final: \(finalMCPs, privacy: .public))")
        } catch {
            Log.configSync.error("Failed to migrate built-in agent MCP defaults for \(slug, privacy: .public): \(error)")
        }

        return migrated
    }

    private func syncGroups(context: ModelContext) {
        let fileDTOs = ConfigFileManager.readAllGroups()
        let existing = (try? context.fetch(FetchDescriptor<AgentGroup>())) ?? []
        let slugMap = Dictionary(uniqueKeysWithValues: existing.compactMap { e in
            e.configSlug.map { ($0, e) }
        })
        var seenSlugs: Set<String> = []

        // Build agent name → UUID map
        let allAgents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let agentByName: [String: UUID] = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.name, $0.id) })

        for (slug, dto) in fileDTOs {
            seenSlugs.insert(slug)
            let agentIds = dto.agentNames.compactMap { agentByName[$0] }
            let coordinatorId = dto.coordinatorAgentName.flatMap { agentByName[$0] }

            // Convert name-based roles to UUID-based
            var roleMap: [UUID: String] = [:]
            for (agentName, role) in dto.roles ?? [:] {
                if let aid = agentByName[agentName] {
                    roleMap[aid] = role
                }
            }

            // Convert workflow steps
            let workflowSteps: [WorkflowStep]? = dto.workflow?.map { step in
                WorkflowStep(
                    agentId: agentByName[step.agentName] ?? UUID(),
                    instruction: step.instruction,
                    condition: step.condition,
                    autoAdvance: step.autoAdvance,
                    stepLabel: step.label,
                    artifactGate: step.artifactGate
                )
            }

            if let entity = slugMap[slug] {
                entity.name = dto.name
                entity.groupDescription = dto.description
                entity.icon = dto.icon
                entity.color = dto.color
                entity.groupInstruction = dto.instruction
                entity.defaultMission = dto.defaultMission
                entity.agentIds = agentIds
                entity.sortOrder = dto.sortOrder
                entity.autoReplyEnabled = dto.autoReplyEnabled ?? true
                entity.autonomousCapable = dto.autonomousCapable ?? false
                entity.coordinatorAgentId = coordinatorId
                entity.agentRoles = roleMap
                entity.workflow = workflowSteps
                entity.isEnabled = dto.enabled
            } else {
                let byName = existing.first { $0.name == dto.name && $0.configSlug == nil }
                if let entity = byName {
                    entity.configSlug = slug
                    entity.groupDescription = dto.description
                    entity.icon = dto.icon
                    entity.color = dto.color
                    entity.groupInstruction = dto.instruction
                    entity.defaultMission = dto.defaultMission
                    entity.agentIds = agentIds
                    entity.sortOrder = dto.sortOrder
                    entity.autoReplyEnabled = dto.autoReplyEnabled ?? true
                    entity.autonomousCapable = dto.autonomousCapable ?? false
                    entity.coordinatorAgentId = coordinatorId
                    entity.agentRoles = roleMap
                    entity.workflow = workflowSteps
                    entity.isEnabled = dto.enabled
                } else {
                    let entity = AgentGroup(
                        name: dto.name, groupDescription: dto.description,
                        icon: dto.icon, color: dto.color,
                        groupInstruction: dto.instruction, defaultMission: dto.defaultMission,
                        agentIds: agentIds, sortOrder: dto.sortOrder
                    )
                    entity.autoReplyEnabled = dto.autoReplyEnabled ?? true
                    entity.autonomousCapable = dto.autonomousCapable ?? false
                    entity.coordinatorAgentId = coordinatorId
                    entity.agentRoles = roleMap
                    entity.workflow = workflowSteps
                    entity.isEnabled = dto.enabled
                    entity.configSlug = slug
                    entity.origin = .builtin
                    context.insert(entity)
                }
            }
        }

        for entity in existing where entity.configSlug != nil && !seenSlugs.contains(entity.configSlug!) {
            entity.isEnabled = false
        }
    }

    // MARK: - Write-Back (SwiftData → files)

    /// Write an agent back to its config file after UI edit
    func writeBack(agent: Agent) {
        let slug = agent.configSlug ?? ConfigFileManager.slugify(agent.name)
        if agent.configSlug == nil { agent.configSlug = slug }

        // Resolve names from UUIDs
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let allSkills = (try? context.fetch(FetchDescriptor<Skill>())) ?? []
        let allMCPs = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
        let allPerms = (try? context.fetch(FetchDescriptor<PermissionSet>())) ?? []

        let skillNames = agent.skillIds.compactMap { id in allSkills.first { $0.id == id }?.name }
        let mcpNames = agent.extraMCPServerIds.compactMap { id in allMCPs.first { $0.id == id }?.name }
        let permName = agent.permissionSetId.flatMap { id in allPerms.first { $0.id == id }?.name } ?? "Full Access"

        let dto = AgentConfigDTO(
            name: agent.name, enabled: agent.isEnabled, agentDescription: agent.agentDescription,
            provider: agent.provider,
            model: agent.model, icon: agent.icon, color: agent.color,
            skillNames: skillNames, mcpServerNames: mcpNames, permissionSetName: permName,
            systemPromptTemplate: nil, systemPromptVariables: nil,
            maxTurns: agent.maxTurns, maxBudget: agent.maxBudget, maxThinkingTokens: agent.maxThinkingTokens,
            defaultWorkingDirectory: agent.defaultWorkingDirectory,
            instancePolicy: agent.instancePolicy == .agentDefault ? nil : agent.instancePolicy.rawValue,
            instancePolicyPoolMax: agent.instancePolicy == .pool ? agent.instancePolicyPoolMax : nil
        )

        isWritingBack = true
        try? ConfigFileManager.writeAgent(dto, slug: slug)
        // Brief delay before re-enabling watcher response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWritingBack = false
        }
    }

    func writeBack(group: AgentGroup) {
        let slug = group.configSlug ?? ConfigFileManager.slugify(group.name)
        if group.configSlug == nil { group.configSlug = slug }

        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let allAgents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let agentNameById: [UUID: String] = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0.name) })

        let agentNames = group.agentIds.compactMap { agentNameById[$0] }
        let coordinatorName = group.coordinatorAgentId.flatMap { agentNameById[$0] }

        var roles: [String: String] = [:]
        for (agentId, role) in group.agentRoles {
            if let name = agentNameById[agentId] {
                roles[name] = role
            }
        }

        let workflowDTOs: [WorkflowStepDTO]? = group.workflow?.map { step in
            WorkflowStepDTO(
                agentName: agentNameById[step.agentId] ?? "Unknown",
                instruction: step.instruction,
                label: step.stepLabel ?? "",
                autoAdvance: step.autoAdvance,
                condition: step.condition,
                artifactGate: step.artifactGate
            )
        }

        let dto = GroupConfigDTO(
            name: group.name, enabled: group.isEnabled, description: group.groupDescription,
            icon: group.icon, color: group.color, instruction: group.groupInstruction,
            defaultMission: group.defaultMission, agentNames: agentNames, sortOrder: group.sortOrder,
            autoReplyEnabled: group.autoReplyEnabled, autonomousCapable: group.autonomousCapable,
            coordinatorAgentName: coordinatorName, roles: roles.isEmpty ? nil : roles,
            workflow: workflowDTOs
        )

        isWritingBack = true
        try? ConfigFileManager.writeGroup(dto, slug: slug)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWritingBack = false
        }
    }

    func writeBack(skill: Skill) {
        let slug = skill.configSlug ?? ConfigFileManager.slugify(skill.name)
        if skill.configSlug == nil { skill.configSlug = slug }

        let dto = SkillFrontmatterDTO(
            name: skill.name, description: skill.skillDescription, category: skill.category,
            enabled: skill.isEnabled, triggers: skill.triggers, version: skill.version,
            mcpServerNames: [], content: skill.content
        )

        isWritingBack = true
        try? ConfigFileManager.writeSkill(dto, slug: slug)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWritingBack = false
        }
    }

    func writeBack(mcp: MCPServer) {
        let slug = mcp.configSlug ?? ConfigFileManager.slugify(mcp.name)
        if mcp.configSlug == nil { mcp.configSlug = slug }

        let dto: MCPConfigDTO
        switch mcp.transport {
        case .stdio(let command, let args, let env):
            dto = MCPConfigDTO(
                name: mcp.name, enabled: mcp.isEnabled, serverDescription: mcp.serverDescription,
                transportKind: "stdio", transportCommand: command, transportArgs: args,
                transportEnv: env, transportUrl: nil, transportHeaders: nil
            )
        case .http(let url, let headers):
            dto = MCPConfigDTO(
                name: mcp.name, enabled: mcp.isEnabled, serverDescription: mcp.serverDescription,
                transportKind: "http", transportCommand: nil, transportArgs: nil,
                transportEnv: nil, transportUrl: url, transportHeaders: headers
            )
        }

        isWritingBack = true
        try? ConfigFileManager.writeMCP(dto, slug: slug)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWritingBack = false
        }
    }

    func writeBack(permission: PermissionSet) {
        let slug = permission.configSlug ?? ConfigFileManager.slugify(permission.name)
        if permission.configSlug == nil { permission.configSlug = slug }

        let dto = PermissionConfigDTO(
            name: permission.name, enabled: permission.isEnabled,
            allowRules: permission.allowRules, denyRules: permission.denyRules,
            additionalDirectories: permission.additionalDirectories,
            permissionMode: permission.permissionMode
        )

        isWritingBack = true
        try? ConfigFileManager.writePermission(dto, slug: slug)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWritingBack = false
        }
    }

    // MARK: - Export (SwiftData → files, for migration)

    private func exportCurrentState(context: ModelContext) {
        do {
            try ConfigFileManager.createDirectoryStructure()
        } catch {
            Log.configSync.error("Failed to create directory structure: \(error)")
            return
        }

        // Export permissions
        let permissions = (try? context.fetch(FetchDescriptor<PermissionSet>())) ?? []
        for perm in permissions {
            let slug = ConfigFileManager.slugify(perm.name)
            perm.configSlug = slug
            let dto = PermissionConfigDTO(
                name: perm.name, enabled: true, allowRules: perm.allowRules,
                denyRules: perm.denyRules, additionalDirectories: perm.additionalDirectories,
                permissionMode: perm.permissionMode
            )
            try? ConfigFileManager.writePermission(dto, slug: slug)
        }

        // Export MCPs
        let mcps = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
        for mcp in mcps {
            let slug = ConfigFileManager.slugify(mcp.name)
            mcp.configSlug = slug
            writeBack(mcp: mcp)
        }

        // Export skills
        let skills = (try? context.fetch(FetchDescriptor<Skill>())) ?? []
        for skill in skills {
            let slug = ConfigFileManager.slugify(skill.name)
            skill.configSlug = slug
            writeBack(skill: skill)
        }

        // Export agents
        let agents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        for agent in agents {
            let slug = ConfigFileManager.slugify(agent.name)
            agent.configSlug = slug
            writeBack(agent: agent)
        }

        // Export groups
        let groups = (try? context.fetch(FetchDescriptor<AgentGroup>())) ?? []
        for group in groups {
            let slug = ConfigFileManager.slugify(group.name)
            group.configSlug = slug
            writeBack(group: group)
        }

        // Export templates
        // Templates are only in bundle, copy them
        try? ConfigFileManager.copyFactoryDefaults()

        // Also create .factory/ reference
        try? ConfigFileManager.copyFactoryDefaults()

        try? context.save()
        isWritingBack = false
        Log.configSync.info("Export complete")
    }

    // MARK: - Factory Reset

    func factoryReset() {
        do {
            try ConfigFileManager.factoryReset()
            performFullSync()
            Log.configSync.info("Factory reset complete")
        } catch {
            Log.configSync.error("Factory reset failed: \(error)")
        }
    }

    func restoreFactoryDefault(entityType: String, slug: String) {
        if ConfigFileManager.restoreFactoryDefault(entityType: entityType, slug: slug) {
            performFullSync()
        }
    }

    func restoreFactoryDefaults(entityType: String) {
        do {
            try ConfigFileManager.restoreFactoryDefaults(entityType: entityType)
            performFullSync()
        } catch {
            Log.configSync.error("Failed to restore \(entityType, privacy: .public) defaults: \(error)")
        }
    }

    // MARK: - File Watcher

    private func startFileWatcher() {
        guard !isWatching else { return }

        let subdirs = ["agents", "groups", "skills", "mcps", "permissions", "templates"]
        var allDirs = [ConfigFileManager.configDirectory]
        for sub in subdirs {
            allDirs.append(ConfigFileManager.configDirectory.appendingPathComponent(sub))
        }

        for dir in allDirs {
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: debounceQueue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleSync()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            dispatchSources.append(source)
        }

        isWatching = true
        Log.configSync.info("File watcher started on \(allDirs.count) directories")
    }

    private func stopFileWatcher() {
        for source in dispatchSources {
            source.cancel()
        }
        dispatchSources.removeAll()
        fileDescriptors.removeAll()
        isWatching = false
    }

    private func scheduleSync() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isWritingBack else { return }
            DispatchQueue.main.async {
                self.performFullSync()
            }
        }
        debounceWorkItem = item
        debounceQueue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    // MARK: - Helpers

    private func resolveSystemPrompt(dto: AgentConfigDTO, templates: [String: String]) -> String {
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

    private func applyTransport(dto: MCPConfigDTO, to entity: MCPServer) {
        if dto.transportKind == "stdio" {
            entity.transport = .stdio(
                command: dto.transportCommand ?? "",
                args: dto.transportArgs ?? [],
                env: dto.transportEnv ?? [:]
            )
        } else {
            entity.transport = .http(
                url: dto.transportUrl ?? "",
                headers: dto.transportHeaders ?? [:]
            )
        }
    }

    private func makeTransport(from dto: MCPConfigDTO) -> MCPTransport {
        if dto.transportKind == "stdio" {
            return .stdio(command: dto.transportCommand ?? "", args: dto.transportArgs ?? [], env: dto.transportEnv ?? [:])
        } else {
            return .http(url: dto.transportUrl ?? "", headers: dto.transportHeaders ?? [:])
        }
    }
}
