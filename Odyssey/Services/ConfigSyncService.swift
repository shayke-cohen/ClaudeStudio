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
        // Note: performFullSync() also calls syncFeaturesFromDisk() for features.json support.
        performFullSync()

        // One-time migration: pin Friday by default
        let fridayPinnedKey = "odyssey.migration.fridayPinned"
        if !InstanceConfig.userDefaults.bool(forKey: fridayPinnedKey) {
            let ctx = ModelContext(container)
            var pred = FetchDescriptor<Agent>()
            pred.predicate = #Predicate { $0.configSlug == "friday" }
            if let friday = (try? ctx.fetch(pred))?.first, !friday.isResident {
                friday.isResident = true
                try? ctx.save()
            }
            InstanceConfig.userDefaults.set(true, forKey: fridayPinnedKey)
        }

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
        ConfigFileManager.syncBundledPromptTemplates(overwriteExisting: overwriteExisting)

        // Sync bundled Catalog entries for the new file-backed format (no-ops until catalog migration populates them)
        ConfigFileManager.syncBundledAgents()
        ConfigFileManager.syncBundledGroups()
        try? ConfigFileManager.syncBundledSkills()
        try? ConfigFileManager.syncBundledMCPs()

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
        // Run as an async Task so each yield point lets the run loop process UI events,
        // preventing the 200-500ms main-thread stall from 254+ file reads.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let context = ModelContext(container)

            Log.configSync.info("Starting full sync")

            let templates = ConfigFileManager.readAllTemplates()
            await Task.yield()

            syncPermissions(context: context)
            syncMCPs(context: context)
            await Task.yield()

            syncSkills(context: context)
            syncAgents(context: context, templates: templates)
            await Task.yield()

            syncGroups(context: context)
            syncPromptTemplates(context: context)
            await Task.yield()

            syncAgentFiles(context: context)
            syncGroupFiles(context: context)
            syncSkillFiles(context: context)
            syncMCPFiles(context: context)
            await Task.yield()

            syncFeaturesFromDisk()
            repairResidentHomeFolders(context: context)
            repairGroupHomeFolders(context: context)

            do {
                if context.hasChanges {
                    try context.save()
                    Log.configSync.info("Full sync complete (saved changes)")
                } else {
                    Log.configSync.info("Full sync complete (no changes)")
                }
            } catch {
                Log.configSync.error("Failed to save: \(error)")
            }
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
            // Only disable if this agent isn't managed by the file-backed (subdirectory) format.
            // File-backed agents (e.g. daily-news-digest/config.json) are handled by syncAgentFiles().
            let fileBackedDir = ConfigFileManager.agentsDirectory.appendingPathComponent(entity.configSlug!)
            let isFileBacked = FileManager.default.fileExists(atPath: fileBackedDir.appendingPathComponent("config.json").path)
            if !isFileBacked {
                entity.isEnabled = false
            }
        }
    }

    /// Ensures every agent has a defaultWorkingDirectory.
    /// Agents created before the home-folder feature shipped (including built-ins) may have a nil path.
    private func repairResidentHomeFolders(context: ModelContext) {
        let allAgents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        var repaired = 0
        for agent in allAgents {
            if agent.defaultWorkingDirectory == nil || agent.defaultWorkingDirectory!.isEmpty {
                agent.defaultWorkingDirectory = Agent.defaultHomePath(for: agent.name)
                repaired += 1
            }
        }
        if repaired > 0 {
            Log.configSync.info("Repaired home folder for \(repaired) agent(s)")
        }
    }

    private func repairGroupHomeFolders(context: ModelContext) {
        let allGroups = (try? context.fetch(FetchDescriptor<AgentGroup>())) ?? []
        var repaired = 0
        for group in allGroups {
            if group.defaultWorkingDirectory == nil || group.defaultWorkingDirectory!.isEmpty {
                group.defaultWorkingDirectory = AgentGroup.defaultHomePath(for: group.name)
                repaired += 1
            }
        }
        if repaired > 0 {
            Log.configSync.info("Repaired home folder for \(repaired) group(s)")
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
        let slugMap = Dictionary(existing.compactMap { e in e.configSlug.map { ($0, e) } },
                                 uniquingKeysWith: { first, _ in first })
        var seenSlugs: Set<String> = []

        // Build agent name → UUID map
        let allAgents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let agentByName: [String: UUID] = Dictionary(allAgents.map { ($0.name, $0.id) },
                                                     uniquingKeysWith: { first, _ in first })

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
            // Only disable if not managed by file-backed (subdirectory) format
            let fileBackedDir = ConfigFileManager.groupsDirectory.appendingPathComponent(entity.configSlug!)
            let isFileBacked = FileManager.default.fileExists(atPath: fileBackedDir.appendingPathComponent("config.json").path)
            if !isFileBacked {
                entity.isEnabled = false
            }
        }
    }

    // MARK: - File-Backed Entity Sync (new subdirectory / slug-file format)

    // MARK: Agents

    private func syncAgentFiles(context: ModelContext) {
        let fileEntries = ConfigFileManager.readAllAgentFiles()
        let existing = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let slugMap = Dictionary(uniqueKeysWithValues: existing.compactMap { e in
            e.configSlug.map { ($0, e) }
        })

        // Pre-build lookup maps for slug → UUID resolution
        let allSkills = (try? context.fetch(FetchDescriptor<Skill>())) ?? []
        let skillBySlug: [String: UUID] = Dictionary(uniqueKeysWithValues: allSkills.compactMap { s in
            s.configSlug.map { ($0, s.id) }
        })
        let allMCPs = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
        let mcpBySlug: [String: UUID] = Dictionary(uniqueKeysWithValues: allMCPs.compactMap { m in
            m.configSlug.map { ($0, m.id) }
        })
        let allPerms = (try? context.fetch(FetchDescriptor<PermissionSet>())) ?? []
        let permBySlug: [String: UUID] = Dictionary(uniqueKeysWithValues: allPerms.compactMap { p in
            p.configSlug.map { ($0, p.id) }
        })

        var seenSlugs: Set<String> = []

        for entry in fileEntries {
            let slug = entry.slug
            seenSlugs.insert(slug)

            // Resolve slug references to UUIDs
            let skillIds: [UUID] = entry.config.skills.compactMap { skillSlug in
                if let id = skillBySlug[skillSlug] { return id }
                Log.configSync.warning("syncAgentFiles: unresolvable skill slug '\(skillSlug, privacy: .public)' for agent '\(slug, privacy: .public)' — skipped")
                return nil
            }
            let mcpIds: [UUID] = entry.config.mcps.compactMap { mcpSlug in
                if let id = mcpBySlug[mcpSlug] { return id }
                Log.configSync.warning("syncAgentFiles: unresolvable MCP slug '\(mcpSlug, privacy: .public)' for agent '\(slug, privacy: .public)' — skipped")
                return nil
            }
            let permId: UUID? = entry.config.permissions.flatMap { permSlug in
                if let id = permBySlug[permSlug] { return id }
                Log.configSync.warning("syncAgentFiles: unresolvable permission slug '\(permSlug, privacy: .public)' for agent '\(slug, privacy: .public)' — skipped")
                return nil
            }

            if let entity = slugMap[slug] {
                // Update existing
                entity.name = entry.config.name
                entity.agentDescription = entry.config.description ?? ""
                entity.systemPrompt = entry.prompt
                entity.provider = entry.config.provider ?? ProviderSelection.system.rawValue
                entity.model = entry.config.model
                entity.icon = entry.config.icon ?? ""
                entity.color = entry.config.color ?? ""
                entity.skillIds = skillIds
                entity.extraMCPServerIds = mcpIds
                entity.permissionSetId = permId
                entity.maxTurns = entry.config.maxTurns
                entity.maxBudget = entry.config.maxBudget
                entity.maxThinkingTokens = entry.config.maxThinkingTokens
                entity.defaultWorkingDirectory = entry.config.defaultWorkingDirectory
                entity.isEnabled = true
                entity.instancePolicy = AgentInstancePolicy(rawValue: entry.config.instancePolicy ?? "") ?? .agentDefault
                entity.instancePolicyPoolMax = entry.config.instancePolicyPoolMax
                if let isShared = entry.config.isShared { entity.isShared = isShared }
                entity.configSlug = slug
                entity.updatedAt = Date()
            } else {
                // Check for a name-match migration candidate (no configSlug yet)
                let byName = existing.first { $0.name == entry.config.name && $0.configSlug == nil }
                if let entity = byName {
                    entity.configSlug = slug
                    entity.agentDescription = entry.config.description ?? ""
                    entity.systemPrompt = entry.prompt
                    entity.provider = entry.config.provider ?? ProviderSelection.system.rawValue
                    entity.model = entry.config.model
                    entity.icon = entry.config.icon ?? ""
                    entity.color = entry.config.color ?? ""
                    entity.skillIds = skillIds
                    entity.extraMCPServerIds = mcpIds
                    entity.permissionSetId = permId
                    entity.maxTurns = entry.config.maxTurns
                    entity.maxBudget = entry.config.maxBudget
                    entity.maxThinkingTokens = entry.config.maxThinkingTokens
                    entity.defaultWorkingDirectory = entry.config.defaultWorkingDirectory
                    entity.instancePolicy = AgentInstancePolicy(rawValue: entry.config.instancePolicy ?? "") ?? .agentDefault
                    entity.instancePolicyPoolMax = entry.config.instancePolicyPoolMax
                    if let isShared = entry.config.isShared { entity.isShared = isShared }
                    entity.updatedAt = Date()
                } else {
                    // Insert new
                    let entity = Agent(
                        name: entry.config.name,
                        agentDescription: entry.config.description ?? "",
                        systemPrompt: entry.prompt,
                        provider: entry.config.provider ?? ProviderSelection.system.rawValue,
                        model: entry.config.model,
                        icon: entry.config.icon ?? "",
                        color: entry.config.color ?? ""
                    )
                    entity.skillIds = skillIds
                    entity.extraMCPServerIds = mcpIds
                    entity.permissionSetId = permId
                    entity.maxTurns = entry.config.maxTurns
                    entity.maxBudget = entry.config.maxBudget
                    entity.maxThinkingTokens = entry.config.maxThinkingTokens
                    entity.defaultWorkingDirectory = entry.config.defaultWorkingDirectory
                    entity.instancePolicy = AgentInstancePolicy(rawValue: entry.config.instancePolicy ?? "") ?? .agentDefault
                    entity.instancePolicyPoolMax = entry.config.instancePolicyPoolMax
                    if let isShared = entry.config.isShared { entity.isShared = isShared }
                    if let resident = entry.config.resident { entity.isResident = resident }
                    entity.configSlug = slug
                    entity.origin = .builtin
                    context.insert(entity)
                }
            }
        }

        // Soft-disable entities whose file-backed directories were removed.
        // Only touch agents that are in the file-backed format (subdirectory with config.json).
        // Skip flat-format agents (e.g. coder.json) — those are managed by syncAgents().
        for entity in existing where entity.configSlug != nil && !seenSlugs.contains(entity.configSlug!) {
            let fileBackedDir = ConfigFileManager.agentsDirectory.appendingPathComponent(entity.configSlug!)
            let hasFlatFile = FileManager.default.fileExists(
                atPath: ConfigFileManager.agentsDirectory.appendingPathComponent(entity.configSlug! + ".json").path
            )
            // Only disable if this was a file-backed agent (not flat-format) and the directory is gone
            if !hasFlatFile
                && !FileManager.default.fileExists(atPath: fileBackedDir.path + "/config.json")
                && !seenSlugs.isEmpty {
                entity.isEnabled = false
            }
        }
    }

    // MARK: Groups

    private func syncGroupFiles(context: ModelContext) {
        let fileEntries = ConfigFileManager.readAllGroupFiles()
        let existing = (try? context.fetch(FetchDescriptor<AgentGroup>())) ?? []
        let slugMap = Dictionary(existing.compactMap { e in e.configSlug.map { ($0, e) } },
                                 uniquingKeysWith: { first, _ in first })

        // Build agent slug → UUID map
        let allAgents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let agentBySlug: [String: UUID] = Dictionary(allAgents.compactMap { a in a.configSlug.map { ($0, a.id) } },
                                                     uniquingKeysWith: { first, _ in first })

        var seenSlugs: Set<String> = []

        for entry in fileEntries {
            let slug = entry.slug
            seenSlugs.insert(slug)

            // Resolve agent slugs → UUIDs
            let agentIds: [UUID] = entry.config.agents.compactMap { agentSlug in
                if let id = agentBySlug[agentSlug] { return id }
                Log.configSync.warning("syncGroupFiles: unresolvable agent slug '\(agentSlug, privacy: .public)' for group '\(slug, privacy: .public)' — skipped")
                return nil
            }
            let coordinatorId: UUID? = entry.config.coordinator.flatMap { agentSlug in
                if let id = agentBySlug[agentSlug] { return id }
                Log.configSync.warning("syncGroupFiles: unresolvable coordinator slug '\(agentSlug, privacy: .public)' for group '\(slug, privacy: .public)' — skipped")
                return nil
            }
            var roleMap: [UUID: String] = [:]
            for (agentSlug, roleName) in entry.config.roles ?? [:] {
                if let id = agentBySlug[agentSlug] {
                    roleMap[id] = roleName
                } else {
                    Log.configSync.warning("syncGroupFiles: unresolvable role agent slug '\(agentSlug, privacy: .public)' for group '\(slug, privacy: .public)' — skipped")
                }
            }

            // Convert workflow steps
            let workflowSteps: [WorkflowStep]? = entry.workflow?.compactMap { step in
                guard let agentId = agentBySlug[step.agent] else {
                    Log.configSync.warning("syncGroupFiles: unresolvable workflow agent slug '\(step.agent, privacy: .public)' for group '\(slug, privacy: .public)' — step skipped")
                    return nil
                }
                let gate: WorkflowArtifactGate? = step.artifactGate.map {
                    WorkflowArtifactGate(
                        profile: $0.profile,
                        approvalRequired: $0.approvalRequired,
                        publishRepoDoc: $0.publishRepoDoc,
                        blockedDownstreamAgentNames: $0.blockedDownstreamAgentNames
                    )
                }
                return WorkflowStep(
                    agentId: agentId,
                    instruction: step.instruction,
                    condition: step.condition,
                    autoAdvance: step.autoAdvance ?? false,
                    stepLabel: step.stepLabel,
                    artifactGate: gate
                )
            }

            if let entity = slugMap[slug] {
                entity.name = entry.config.name
                entity.groupDescription = entry.config.description ?? ""
                entity.icon = entry.config.icon ?? ""
                entity.color = entry.config.color ?? ""
                entity.groupInstruction = entry.instruction
                entity.defaultMission = entry.mission
                entity.agentIds = agentIds
                entity.autoReplyEnabled = entry.config.autoReplyEnabled ?? true
                entity.autonomousCapable = entry.config.autonomousCapable ?? false
                entity.coordinatorAgentId = coordinatorId
                entity.agentRoles = roleMap
                entity.isEnabled = true
                entity.workflow = workflowSteps
            } else {
                let byName = existing.first { $0.name == entry.config.name && $0.configSlug == nil }
                if let entity = byName {
                    entity.configSlug = slug
                    entity.groupDescription = entry.config.description ?? ""
                    entity.icon = entry.config.icon ?? ""
                    entity.color = entry.config.color ?? ""
                    entity.groupInstruction = entry.instruction
                    entity.defaultMission = entry.mission
                    entity.agentIds = agentIds
                    entity.autoReplyEnabled = entry.config.autoReplyEnabled ?? true
                    entity.autonomousCapable = entry.config.autonomousCapable ?? false
                    entity.coordinatorAgentId = coordinatorId
                    entity.agentRoles = roleMap
                    entity.workflow = workflowSteps
                } else {
                    let entity = AgentGroup(
                        name: entry.config.name,
                        groupDescription: entry.config.description ?? "",
                        icon: entry.config.icon ?? "",
                        color: entry.config.color ?? "",
                        groupInstruction: entry.instruction,
                        defaultMission: entry.mission,
                        agentIds: agentIds
                    )
                    entity.autoReplyEnabled = entry.config.autoReplyEnabled ?? true
                    entity.autonomousCapable = entry.config.autonomousCapable ?? false
                    entity.coordinatorAgentId = coordinatorId
                    entity.agentRoles = roleMap
                    entity.workflow = workflowSteps
                    entity.configSlug = slug
                    entity.origin = .builtin
                    context.insert(entity)
                }
            }
        }
        // File-backed groups: soft-disable is handled conservatively (legacy syncGroups owns the disable path)
    }

    // MARK: Skills (flat {slug}.md files)

    private func syncSkillFiles(context: ModelContext) {
        let fileEntries = ConfigFileManager.readAllSkillFiles()
        let existing = (try? context.fetch(FetchDescriptor<Skill>())) ?? []
        let slugMap = Dictionary(uniqueKeysWithValues: existing.compactMap { e in
            e.configSlug.map { ($0, e) }
        })
        var seenSlugs: Set<String> = []

        for entry in fileEntries {
            let slug = entry.slug
            seenSlugs.insert(slug)

            if let entity = slugMap[slug] {
                entity.name = entry.dto.name
                entity.category = entry.dto.category ?? "General"
                entity.triggers = entry.dto.triggers ?? []
                entity.content = entry.content
                entity.sourceKind = "filesystem"
                entity.updatedAt = Date()
            } else {
                let byName = existing.first { $0.name == entry.dto.name && $0.configSlug == nil }
                if let entity = byName {
                    entity.configSlug = slug
                    entity.category = entry.dto.category ?? "General"
                    entity.triggers = entry.dto.triggers ?? []
                    entity.content = entry.content
                    entity.sourceKind = "filesystem"
                    entity.updatedAt = Date()
                } else {
                    let entity = Skill(
                        name: entry.dto.name,
                        skillDescription: "",
                        category: entry.dto.category ?? "General",
                        content: entry.content
                    )
                    entity.triggers = entry.dto.triggers ?? []
                    entity.configSlug = slug
                    entity.sourceKind = "filesystem"
                    context.insert(entity)
                }
            }
        }

        // Soft-disable skills whose flat .md files were removed
        for entity in existing {
            guard let slug = entity.configSlug,
                  entity.sourceKind == "filesystem",
                  !seenSlugs.contains(slug) else { continue }
            entity.isEnabled = false
        }
    }

    // MARK: MCPs (flat {slug}.json files in new MCPConfigFileDTO format)

    private func syncMCPFiles(context: ModelContext) {
        let fileEntries = ConfigFileManager.readAllMCPFiles()
        let existing = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
        let slugMap = Dictionary(uniqueKeysWithValues: existing.compactMap { e in
            e.configSlug.map { ($0, e) }
        })
        var seenSlugs: Set<String> = []

        for entry in fileEntries {
            let slug = entry.slug
            seenSlugs.insert(slug)

            let transport: MCPTransport = {
                if entry.dto.transport == "stdio" {
                    return .stdio(
                        command: entry.dto.command ?? "",
                        args: entry.dto.args ?? [],
                        env: entry.dto.env ?? [:]
                    )
                } else {
                    return .http(
                        url: entry.dto.url ?? "",
                        headers: entry.dto.headers ?? [:]
                    )
                }
            }()

            if let entity = slugMap[slug] {
                entity.name = entry.dto.name
                entity.serverDescription = entry.dto.description ?? ""
                entity.transport = transport
            } else {
                let byName = existing.first { $0.name == entry.dto.name && $0.configSlug == nil }
                if let entity = byName {
                    entity.configSlug = slug
                    entity.serverDescription = entry.dto.description ?? ""
                    entity.transport = transport
                } else {
                    let entity = MCPServer(
                        name: entry.dto.name,
                        serverDescription: entry.dto.description ?? "",
                        transport: transport
                    )
                    entity.configSlug = slug
                    context.insert(entity)
                }
            }
        }

        // Soft-disable MCPs whose new-format files were removed.
        // TODO: Safe soft-disable for file-backed MCPs requires a sourceKind field on MCPServer
        // (analogous to Skill.sourceKind) to distinguish file-backed vs catalog entities.
        // Without it, this loop would incorrectly disable catalog MCPs (octocode, argus, etc.)
        // whose configSlug appears in the existing[] set but not in seenSlugs.
        // entity.isEnabled = false  — deferred until MCPServer.sourceKind is added.
        for entity in existing {
            guard let slug = entity.configSlug, !seenSlugs.contains(slug) else { continue }
            // Intentionally not disabling here — see TODO above.
            _ = slug
        }
    }

    // MARK: - File-Backed Write-Back (new subdirectory / slug-file format)

    /// Slug derivation helper — delegates to ConfigFileManager.slugify.
    private func deriveSlug(from name: String) -> String {
        ConfigFileManager.slugify(name)
    }

    /// Write an agent back to its file-backed config directory (agents/{slug}/config.json + prompt.md).
    func writeBack(_ agent: Agent) throws {
        guard !isWritingBack else { return }
        let slug = agent.configSlug ?? deriveSlug(from: agent.name)
        if agent.configSlug == nil { agent.configSlug = slug }

        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let allSkills = (try? context.fetch(FetchDescriptor<Skill>())) ?? []
        let allMCPs = (try? context.fetch(FetchDescriptor<MCPServer>())) ?? []
        let allPerms = (try? context.fetch(FetchDescriptor<PermissionSet>())) ?? []

        let skillSlugs = agent.skillIds.compactMap { id -> String? in
            guard let skill = allSkills.first(where: { $0.id == id }) else { return nil }
            return skill.configSlug ?? deriveSlug(from: skill.name)
        }
        let mcpSlugs = agent.extraMCPServerIds.compactMap { id -> String? in
            guard let mcp = allMCPs.first(where: { $0.id == id }) else { return nil }
            return mcp.configSlug ?? deriveSlug(from: mcp.name)
        }
        let permSlug: String? = agent.permissionSetId.flatMap { id in
            guard let perm = allPerms.first(where: { $0.id == id }) else { return nil }
            return perm.configSlug ?? deriveSlug(from: perm.name)
        }

        let config = AgentConfigFileDTO(
            name: agent.name,
            description: agent.agentDescription.isEmpty ? nil : agent.agentDescription,
            model: agent.model,
            provider: agent.provider == ProviderSelection.system.rawValue ? nil : agent.provider,
            resident: agent.isResident ? true : nil,
            icon: agent.icon.isEmpty ? nil : agent.icon,
            color: agent.color.isEmpty ? nil : agent.color,
            skills: skillSlugs,
            mcps: mcpSlugs,
            permissions: permSlug,
            maxTurns: agent.maxTurns,
            maxBudget: agent.maxBudget,
            maxThinkingTokens: agent.maxThinkingTokens,
            instancePolicy: agent.instancePolicy == .agentDefault ? nil : agent.instancePolicy.rawValue,
            instancePolicyPoolMax: agent.instancePolicy == .pool ? agent.instancePolicyPoolMax : nil,
            defaultWorkingDirectory: agent.defaultWorkingDirectory,
            isShared: agent.isShared ? true : nil
        )

        isWritingBack = true
        do {
            try ConfigFileManager.writeBack(agentSlug: slug, config: config, prompt: agent.systemPrompt)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isWritingBack = false
            }
        } catch {
            isWritingBack = false
            throw error
        }
    }

    /// Write a group back to its file-backed config directory (groups/{slug}/config.json + instruction.md + …).
    func writeBack(_ group: AgentGroup) throws {
        guard !isWritingBack else { return }
        let slug = group.configSlug ?? deriveSlug(from: group.name)
        if group.configSlug == nil { group.configSlug = slug }

        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let allAgents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []

        let agentSlugById: [UUID: String] = Dictionary(uniqueKeysWithValues: allAgents.compactMap { a -> (UUID, String)? in
            let s = a.configSlug ?? deriveSlug(from: a.name)
            return (a.id, s)
        })

        let agentSlugs = group.agentIds.compactMap { agentSlugById[$0] }
        let coordinatorSlug = group.coordinatorAgentId.flatMap { agentSlugById[$0] }

        var roles: [String: String] = [:]
        for (agentId, roleName) in group.agentRoles {
            if let agentSlug = agentSlugById[agentId] {
                roles[agentSlug] = roleName
            }
        }

        let workflowSteps: [WorkflowStepFileDTO]? = group.workflow?.map { step in
            let agentSlug = agentSlugById[step.agentId] ?? "unknown"
            let gate: WorkflowArtifactGateFileDTO? = step.artifactGate.map {
                WorkflowArtifactGateFileDTO(
                    profile: $0.profile,
                    approvalRequired: $0.approvalRequired,
                    publishRepoDoc: $0.publishRepoDoc,
                    blockedDownstreamAgentNames: $0.blockedDownstreamAgentNames
                )
            }
            return WorkflowStepFileDTO(
                id: step.id.uuidString,
                agent: agentSlug,
                instruction: step.instruction,
                stepLabel: step.stepLabel,
                autoAdvance: step.autoAdvance,
                condition: step.condition,
                artifactGate: gate
            )
        }

        // AgentGroup has no workingDirectory, model, or extraMCPServerIds fields,
        // so those GroupConfigFileDTO fields remain nil.
        let config = GroupConfigFileDTO(
            name: group.name,
            description: group.groupDescription.isEmpty ? nil : group.groupDescription,
            agents: agentSlugs,
            workingDirectory: nil,
            model: nil,
            mcps: nil,
            icon: group.icon.isEmpty ? nil : group.icon,
            color: group.color.isEmpty ? nil : group.color,
            autoReplyEnabled: group.autoReplyEnabled,
            autonomousCapable: group.autonomousCapable,
            coordinator: coordinatorSlug,
            routingMode: nil,
            roles: roles.isEmpty ? nil : roles
        )

        isWritingBack = true
        do {
            try ConfigFileManager.writeBack(
                groupSlug: slug,
                config: config,
                instruction: group.groupInstruction,
                mission: group.defaultMission,
                workflow: workflowSteps
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isWritingBack = false
            }
        } catch {
            isWritingBack = false
            throw error
        }
    }

    /// Write a skill back to its flat file-backed format (skills/{slug}.md).
    func writeBack(_ skill: Skill) throws {
        guard !isWritingBack else { return }
        let slug = skill.configSlug ?? deriveSlug(from: skill.name)
        if skill.configSlug == nil { skill.configSlug = slug }

        let dto = SkillFileDTO(
            name: skill.name,
            category: skill.category.isEmpty ? nil : skill.category,
            triggers: skill.triggers.isEmpty ? nil : skill.triggers
        )

        isWritingBack = true
        do {
            try ConfigFileManager.writeBack(skillSlug: slug, dto: dto, content: skill.content)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isWritingBack = false
            }
        } catch {
            isWritingBack = false
            throw error
        }
    }

    /// Write an MCP server back to its flat file-backed format (mcps/{slug}.json).
    func writeBack(_ mcpServer: MCPServer) throws {
        guard !isWritingBack else { return }
        let slug = mcpServer.configSlug ?? deriveSlug(from: mcpServer.name)
        if mcpServer.configSlug == nil { mcpServer.configSlug = slug }

        let dto: MCPConfigFileDTO
        switch mcpServer.transport {
        case .stdio(let command, let args, let env):
            dto = MCPConfigFileDTO(
                name: mcpServer.name,
                description: mcpServer.serverDescription.isEmpty ? nil : mcpServer.serverDescription,
                transport: "stdio",
                command: command,
                args: args.isEmpty ? nil : args,
                env: env.isEmpty ? nil : env,
                url: nil,
                headers: nil
            )
        case .http(let url, let headers):
            dto = MCPConfigFileDTO(
                name: mcpServer.name,
                description: mcpServer.serverDescription.isEmpty ? nil : mcpServer.serverDescription,
                transport: "http",
                command: nil,
                args: nil,
                env: nil,
                url: url,
                headers: headers.isEmpty ? nil : headers
            )
        case .builtin:
            // Built-in servers (e.g. browser) are not written to external config files.
            return
        }

        isWritingBack = true
        do {
            try ConfigFileManager.writeBack(mcpSlug: slug, dto: dto)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isWritingBack = false
            }
        } catch {
            isWritingBack = false
            throw error
        }
    }

    // MARK: - Prompt Templates Sync

    private func syncPromptTemplates(context: ModelContext) {
        let fileEntries = ConfigFileManager.readAllPromptTemplates()
        let existing = (try? context.fetch(FetchDescriptor<PromptTemplate>())) ?? []
        let slugMap = Dictionary(existing.compactMap { template in template.configSlug.map { ($0, template) } },
                                 uniquingKeysWith: { first, _ in first })
        var seenSlugs: Set<String> = []

        // Build owner lookup maps by slug (preferred) then display-name fallback.
        let allAgents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let agentBySlug: [String: Agent] = Dictionary(allAgents.compactMap { agent in agent.configSlug.map { ($0, agent) } },
                                                      uniquingKeysWith: { first, _ in first })
        let agentByDerivedSlug: [String: Agent] = Dictionary(allAgents.map { (ConfigFileManager.slugify($0.name), $0) },
                                                             uniquingKeysWith: { first, _ in first })
        let allGroups = (try? context.fetch(FetchDescriptor<AgentGroup>())) ?? []
        let groupBySlug: [String: AgentGroup] = Dictionary(allGroups.compactMap { group in group.configSlug.map { ($0, group) } },
                                                           uniquingKeysWith: { first, _ in first })
        let groupByDerivedSlug: [String: AgentGroup] = Dictionary(allGroups.map { (ConfigFileManager.slugify($0.name), $0) },
                                                                  uniquingKeysWith: { first, _ in first })
        let allProjects: [Project] = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let projectBySlug: [String: Project] = Dictionary(
            allProjects.compactMap { project in
                let slug = ConfigFileManager.projectSlug(for: project.canonicalRootPath)
                return slug.isEmpty ? nil : (slug, project)
            },
            uniquingKeysWith: { first, _ in
                Log.configSync.warning("Project slug collision detected — keeping first project")
                return first
            }
        )

        for entry in fileEntries {
            seenSlugs.insert(entry.configSlug)

            let ownerAgent: Agent? = entry.ownerKind == .agents
                ? (agentBySlug[entry.ownerSlug] ?? agentByDerivedSlug[entry.ownerSlug])
                : nil
            let ownerGroup: AgentGroup? = entry.ownerKind == .groups
                ? (groupBySlug[entry.ownerSlug] ?? groupByDerivedSlug[entry.ownerSlug])
                : nil
            let ownerProject: Project? = entry.ownerKind == .projects
                ? projectBySlug[entry.ownerSlug]
                : nil

            // Skip files whose owner can't be resolved (e.g. agent renamed to a new slug).
            // They stay on disk; the owner can be re-linked once its slug matches.
            // Exception: projects/_/<slug> are global project templates (no project association needed).
            let isGlobalProjectTemplate = entry.ownerKind == .projects && entry.ownerSlug == "_"
            guard ownerAgent != nil || ownerGroup != nil || ownerProject != nil || isGlobalProjectTemplate else {
                Log.configSync.warning("Prompt template owner not found: \(entry.configSlug, privacy: .public)")
                continue
            }

            if let entity = slugMap[entry.configSlug] {
                entity.name = entry.dto.name
                entity.prompt = entry.dto.prompt
                entity.sortOrder = entry.dto.sortOrder
                entity.agent = ownerAgent
                entity.group = ownerGroup
                entity.project = ownerProject
                entity.updatedAt = Date()
            } else {
                let entity = PromptTemplate(
                    name: entry.dto.name,
                    prompt: entry.dto.prompt,
                    sortOrder: entry.dto.sortOrder,
                    isBuiltin: true,
                    agent: ownerAgent,
                    group: ownerGroup,
                    project: ownerProject,
                    configSlug: entry.configSlug
                )
                context.insert(entity)
            }
        }

        // Any DB row whose file disappeared is removed entirely — unlike other
        // entities (which soft-disable), prompt templates have no isEnabled flag
        // and the disk is the source of truth.
        for entity in existing {
            guard let slug = entity.configSlug else { continue }
            if !seenSlugs.contains(slug) {
                context.delete(entity)
            }
        }

        // Seed all built-in project templates on first run (none exist yet on disk).
        let globalDir = ConfigFileManager.promptTemplatesDirectory
            .appendingPathComponent("projects")
            .appendingPathComponent("_")
        let hasGlobalOnDisk = (try? FileManager.default.contentsOfDirectory(
            at: globalDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ))?.isEmpty == false
        if !hasGlobalOnDisk {
            seedDefaultProjectTemplates(context: context)
        }
    }

    private func seedDefaultProjectTemplates(context: ModelContext) {
        Log.configSync.info("Seeding default global project templates")
        for (index, entry) in ProjectTemplateLibrary.all.enumerated() {
            let templateSlug = ConfigFileManager.uniquePromptTemplateSlug(
                baseName: entry.name,
                ownerKind: .projects,
                ownerSlug: "_"
            )
            let configSlug = "projects/_/\(templateSlug)"
            let dto = PromptTemplateFileDTO(name: entry.name, sortOrder: index + 1, prompt: entry.prompt)
            do {
                try ConfigFileManager.writePromptTemplate(
                    ownerKind: .projects,
                    ownerSlug: "_",
                    templateSlug: templateSlug,
                    dto: dto
                )
            } catch {
                Log.configSync.error("Failed to write default project template '\(entry.name)': \(error)")
                continue
            }
            let template = PromptTemplate(
                name: entry.name,
                prompt: entry.prompt,
                sortOrder: index + 1,
                isBuiltin: true,
                agent: nil,
                group: nil,
                project: nil,
                configSlug: configSlug
            )
            context.insert(template)
        }
    }

    /// Persist a single PromptTemplate to disk. Assumes `configSlug` is already
    /// set; if not, call `beginWritingBack` at the caller.
    func writeBack(promptTemplate template: PromptTemplate) {
        guard let slug = template.configSlug,
              let (ownerKindStr, ownerSlug, templateSlug) = splitPromptTemplateSlug(slug),
              let ownerKind = PromptTemplateOwnerKindOnDisk(rawValue: ownerKindStr) else {
            Log.configSync.warning("writeBack(promptTemplate:) missing/invalid configSlug")
            return
        }

        let dto = PromptTemplateFileDTO(
            name: template.name,
            sortOrder: template.sortOrder,
            prompt: template.prompt
        )

        isWritingBack = true
        try? ConfigFileManager.writePromptTemplate(
            ownerKind: ownerKind, ownerSlug: ownerSlug, templateSlug: templateSlug, dto: dto
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWritingBack = false
        }
    }

    func deleteFile(forPromptTemplate template: PromptTemplate) {
        guard let slug = template.configSlug,
              let (ownerKindStr, ownerSlug, templateSlug) = splitPromptTemplateSlug(slug),
              let ownerKind = PromptTemplateOwnerKindOnDisk(rawValue: ownerKindStr) else { return }
        isWritingBack = true
        try? ConfigFileManager.deletePromptTemplate(
            ownerKind: ownerKind, ownerSlug: ownerSlug, templateSlug: templateSlug
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isWritingBack = false
        }
    }

    private func splitPromptTemplateSlug(_ slug: String) -> (String, String, String)? {
        let parts = slug.split(separator: "/")
        guard parts.count == 3 else { return nil }
        return (String(parts[0]), String(parts[1]), String(parts[2]))
    }

    // MARK: - Feature Flags Sync (features.json → UserDefaults)

    /// URL for the feature-flags file: `~/.odyssey/config/features.json`.
    ///
    /// Format: `{ "workshop": true, "peerNetwork": false, ... }` where keys are the
    /// suffix portion of the full flag key (i.e. without the `odyssey.features.` prefix).
    private static var featuresFileURL: URL {
        ConfigFileManager.configDirectory.appendingPathComponent("features.json")
    }

    /// Reads `features.json` from disk and writes matching values into `AppSettings.store`.
    ///
    /// - Only keys that correspond to known `FeatureFlags.all` entries are applied.
    /// - The file's boolean values overwrite whatever is currently stored in `UserDefaults`.
    /// - If the file is absent or malformed, this is a no-op (existing `UserDefaults` values
    ///   are left intact, so defaults remain in effect).
    func syncFeaturesFromDisk() {
        let url = Self.featuresFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode([String: Bool].self, from: data)

            // Build a lookup: suffix → full key (e.g. "workshop" → "odyssey.features.workshop")
            let suffixToKey: [String: String] = Dictionary(
                uniqueKeysWithValues: FeatureFlags.all.map { key in
                    let suffix = key.replacingOccurrences(of: "odyssey.features.", with: "")
                    return (suffix, key)
                }
            )

            for (suffix, value) in raw {
                guard let fullKey = suffixToKey[suffix] else {
                    Log.configSync.warning("features.json: unknown flag key '\(suffix, privacy: .public)' — skipped")
                    continue
                }
                AppSettings.store.set(value, forKey: fullKey)
            }
            Log.configSync.info("Feature flags synced from features.json (\(raw.count) entries)")
        } catch {
            Log.configSync.error("Failed to read features.json: \(error)")
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
        case .builtin:
            // Built-in servers are not written to config files.
            return
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

    /// Returns a non-isolated DispatchWorkItem suitable for use as a DispatchSource
    /// event handler.  Declared `nonisolated` so the captured closure is NOT
    /// `@MainActor`-isolated — the actual work hops back to `@MainActor` via Task.
    nonisolated private func makeFileWatchEventHandler() -> DispatchWorkItem {
        DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleSync()
            }
        }
    }

    private func startFileWatcher() {
        guard !isWatching else { return }

        let subdirs = ["agents", "groups", "skills", "mcps", "permissions", "templates"]
        var allDirs = [ConfigFileManager.configDirectory]
        for sub in subdirs {
            allDirs.append(ConfigFileManager.configDirectory.appendingPathComponent(sub))
        }
        // Prompt templates live two levels deep (prompt-templates/{agents,groups}/<slug>/).
        // Watch every resolvable directory so in-file edits trigger a resync.
        allDirs.append(contentsOf: ConfigFileManager.promptTemplateWatchDirectories())

        for dir in allDirs {
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: debounceQueue
            )
            // Use a nonisolated handler factory so the DispatchSource fires a
            // non-@MainActor closure on debounceQueue without triggering the
            // Swift 6 actor isolation assertion (_dispatch_assert_queue_fail).
            source.setEventHandler(handler: makeFileWatchEventHandler())
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

    /// Non-isolated factory for the debounce work item.  Must be `nonisolated`
    /// so the DispatchWorkItem closure is NOT `@MainActor`-isolated — calling it
    /// on `debounceQueue` would otherwise trigger `_dispatch_assert_queue_fail`.
    nonisolated private func makeScheduleSyncWorkItem() -> DispatchWorkItem {
        DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isWritingBack else { return }
                self.performFullSync()
            }
        }
    }

    private func scheduleSync() {
        debounceWorkItem?.cancel()
        let item = makeScheduleSyncWorkItem()
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
        } else if dto.transportKind == "builtin" {
            entity.transport = .builtin
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
        } else if dto.transportKind == "builtin" {
            return .builtin
        } else {
            return .http(url: dto.transportUrl ?? "", headers: dto.transportHeaders ?? [:])
        }
    }
}
