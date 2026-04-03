import Foundation
import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class AgentDefaultsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var originalDataDir: String?
    private var originalLegacyDataDir: String?
    private var originalStoredDataDir: String?

    override func setUp() async throws {
        AppSettings.store.removeObject(forKey: AppSettings.defaultProviderKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultClaudeModelKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultCodexModelKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultFoundationModelKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultMLXModelKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultMaxTurnsKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultMaxBudgetKey)
        AppSettings.store.removeObject(forKey: AppSettings.dataDirectoryKey)
        originalDataDir = ProcessInfo.processInfo.environment["ODYSSEY_DATA_DIR"]
        originalLegacyDataDir = ProcessInfo.processInfo.environment["CLAUDESTUDIO_DATA_DIR"]
        originalStoredDataDir = AppSettings.store.string(forKey: AppSettings.dataDirectoryKey)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Skill.self, MCPServer.self, PermissionSet.self, AgentGroup.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        AppSettings.store.removeObject(forKey: AppSettings.defaultProviderKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultClaudeModelKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultCodexModelKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultFoundationModelKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultMLXModelKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultMaxTurnsKey)
        AppSettings.store.removeObject(forKey: AppSettings.defaultMaxBudgetKey)
        if let originalStoredDataDir {
            AppSettings.store.set(originalStoredDataDir, forKey: AppSettings.dataDirectoryKey)
        } else {
            AppSettings.store.removeObject(forKey: AppSettings.dataDirectoryKey)
        }
        if let originalDataDir {
            setenv("ODYSSEY_DATA_DIR", originalDataDir, 1)
        } else {
            unsetenv("ODYSSEY_DATA_DIR")
        }
        if let originalLegacyDataDir {
            setenv("CLAUDESTUDIO_DATA_DIR", originalLegacyDataDir, 1)
        } else {
            unsetenv("CLAUDESTUDIO_DATA_DIR")
        }
        context = nil
        container = nil
    }

    func testSessionInheritsSystemProviderAndModelDefaults() {
        AppSettings.store.set(ProviderSelection.codex.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        let agent = Agent(name: "System Agent")
        let session = Session(agent: agent, workingDirectory: "/tmp")

        XCTAssertEqual(agent.provider, ProviderSelection.system.rawValue)
        XCTAssertEqual(agent.model, AgentDefaults.inheritMarker)
        XCTAssertEqual(session.provider, ProviderSelection.codex.rawValue)
        XCTAssertEqual(session.model, CodexModel.gpt5Codex.rawValue)
    }

    func testFreeformSessionInheritsSystemProviderAndModelDefaults() {
        AppSettings.store.set(ProviderSelection.codex.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        let session = Session(agent: nil, workingDirectory: "/tmp")

        XCTAssertEqual(session.provider, ProviderSelection.codex.rawValue)
        XCTAssertEqual(session.model, CodexModel.gpt5Codex.rawValue)
        XCTAssertEqual(AgentDefaults.displayName(forProvider: session.provider), "Codex")
    }

    func testExplicitAgentProviderUsesProviderSpecificDefaultModelWhenModelInherits() {
        AppSettings.store.set(ProviderSelection.claude.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(ClaudeModel.haiku.rawValue, forKey: AppSettings.defaultClaudeModelKey)

        let agent = Agent(
            name: "Claude Agent",
            provider: ProviderSelection.claude.rawValue,
            model: AgentDefaults.inheritMarker
        )
        let session = Session(agent: agent, workingDirectory: "/tmp")

        XCTAssertEqual(session.provider, ProviderSelection.claude.rawValue)
        XCTAssertEqual(session.model, ClaudeModel.haiku.rawValue)
    }

    func testFoundationProviderUsesFoundationDefaultModelWhenModelInherits() {
        AppSettings.store.set(ProviderSelection.foundation.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(FoundationModel.system.rawValue, forKey: AppSettings.defaultFoundationModelKey)

        let agent = Agent(
            name: "Foundation Agent",
            provider: ProviderSelection.foundation.rawValue,
            model: AgentDefaults.inheritMarker
        )
        let session = Session(agent: agent, workingDirectory: "/tmp")

        XCTAssertEqual(session.provider, ProviderSelection.foundation.rawValue)
        XCTAssertEqual(session.model, FoundationModel.system.rawValue)
        XCTAssertEqual(AgentDefaults.displayName(forProvider: session.provider), "Foundation")
    }

    func testMLXProviderUsesMLXDefaultModelWhenModelInherits() {
        AppSettings.store.set(ProviderSelection.mlx.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set("mlx-community/test-model", forKey: AppSettings.defaultMLXModelKey)

        let agent = Agent(
            name: "MLX Agent",
            provider: ProviderSelection.mlx.rawValue,
            model: AgentDefaults.inheritMarker
        )
        let session = Session(agent: agent, workingDirectory: "/tmp")

        XCTAssertEqual(session.provider, ProviderSelection.mlx.rawValue)
        XCTAssertEqual(session.model, "mlx-community/test-model")
        XCTAssertEqual(AgentDefaults.displayName(forProvider: session.provider), "MLX")
    }

    func testCustomMLXModelIsCompatible() {
        XCTAssertTrue(AgentDefaults.isModel("mlx-community/custom-model", compatibleWith: ProviderSelection.mlx.rawValue))
        XCTAssertEqual(AgentDefaults.normalizedModelSelection("   "), AgentDefaults.inheritMarker)
        XCTAssertTrue(AgentDefaults.isModel("   ", compatibleWith: ProviderSelection.mlx.rawValue))
    }

    func testMLXProviderRejectsClaudeDefaultSelection() {
        AppSettings.store.set(ClaudeModel.sonnet.rawValue, forKey: AppSettings.defaultMLXModelKey)

        XCTAssertEqual(AgentDefaults.defaultModel(for: ProviderSelection.mlx.rawValue), AppSettings.defaultMLXModel)
        XCTAssertEqual(
            AgentDefaults.defaultModelChoiceLabel(for: ProviderSelection.mlx.rawValue),
            "Default (\(AgentDefaults.label(for: AppSettings.defaultMLXModel)))"
        )
    }

    func testAvailableThreadModelChoicesIncludeDownloadedMLXModels() throws {
        let tempDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDataDirectory) }

        AppSettings.store.set(tempDataDirectory.path, forKey: AppSettings.dataDirectoryKey)

        let downloadDirectory = LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: tempDataDirectory.path)
        let manifestURL = URL(fileURLWithPath: LocalProviderInstaller.managedMLXManifestPath(dataDirectoryPath: tempDataDirectory.path))
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let managedPath = URL(fileURLWithPath: downloadDirectory)
            .appendingPathComponent("models/mlx-community/Qwen3-8B-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: managedPath, withIntermediateDirectories: true)

        let manifest = ManagedInstalledMLXManifest(installed: [
            ManagedInstalledMLXModel(
                modelIdentifier: "mlx-community/Qwen3-8B-4bit",
                downloadDirectory: downloadDirectory,
                installedAt: Date(),
                sourceURL: "https://huggingface.co/mlx-community/Qwen3-8B-4bit",
                managedPath: managedPath.path
            )
        ])
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let choices = AgentDefaults.availableThreadModelChoices(for: ProviderSelection.mlx.rawValue)

        XCTAssertTrue(choices.contains(where: { $0.id == "mlx-community/Qwen3-8B-4bit" }))
        XCTAssertTrue(choices.contains(where: { $0.label.contains("Qwen3 8B") }))
    }

    func testAvailableThreadModelChoicesForMLXExcludeTinyInstalledModels() throws {
        let tempDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDataDirectory) }

        AppSettings.store.set(tempDataDirectory.path, forKey: AppSettings.dataDirectoryKey)

        let downloadDirectory = LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: tempDataDirectory.path)
        let manifestURL = URL(fileURLWithPath: LocalProviderInstaller.managedMLXManifestPath(dataDirectoryPath: tempDataDirectory.path))
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let tinyManagedPath = URL(fileURLWithPath: downloadDirectory)
            .appendingPathComponent("models/mlx-community/Llama-3.2-3B-Instruct-4bit", isDirectory: true)
        let strongManagedPath = URL(fileURLWithPath: downloadDirectory)
            .appendingPathComponent("models/mlx-community/Qwen3-8B-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: tinyManagedPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: strongManagedPath, withIntermediateDirectories: true)

        let manifest = ManagedInstalledMLXManifest(installed: [
            ManagedInstalledMLXModel(
                modelIdentifier: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                downloadDirectory: downloadDirectory,
                installedAt: Date(),
                sourceURL: "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit",
                managedPath: tinyManagedPath.path
            ),
            ManagedInstalledMLXModel(
                modelIdentifier: "mlx-community/Qwen3-8B-4bit",
                downloadDirectory: downloadDirectory,
                installedAt: Date(),
                sourceURL: "https://huggingface.co/mlx-community/Qwen3-8B-4bit",
                managedPath: strongManagedPath.path
            )
        ])
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let choices = AgentDefaults.availableThreadModelChoices(for: ProviderSelection.mlx.rawValue)

        XCTAssertFalse(choices.contains(where: { $0.id == "mlx-community/Llama-3.2-3B-Instruct-4bit" }))
        XCTAssertTrue(choices.contains(where: { $0.id == "mlx-community/Qwen3-8B-4bit" }))
    }

    func testEnsureNewSkillsSeedsProductArtifactGateAndAttachesToProductManager() throws {
        let productManager = Agent(name: "Product Manager")
        context.insert(productManager)
        try context.save()

        DefaultsSeeder.ensureNewSkills(container: container)

        let skills = try context.fetch(FetchDescriptor<Skill>())
        let artifactGate = try XCTUnwrap(skills.first(where: { $0.name == "product-artifact-gate" }))
        let refreshedAgents = try context.fetch(FetchDescriptor<Agent>())
        let refreshedProductManager = try XCTUnwrap(refreshedAgents.first(where: { $0.name == "Product Manager" }))
        XCTAssertTrue(artifactGate.content.contains("Do **not** hand work to engineering"))
        XCTAssertTrue(refreshedProductManager.skillIds.contains(artifactGate.id))
    }

    func testEnsureNewSkillsSeedsArtifactHandoffGateAndAttachesToCoreAgents() throws {
        let orchestrator = Agent(name: "Orchestrator")
        let designer = Agent(name: "Designer")
        let tester = Agent(name: "Tester")
        context.insert(orchestrator)
        context.insert(designer)
        context.insert(tester)
        try context.save()

        DefaultsSeeder.ensureNewSkills(container: container)

        let skills = try context.fetch(FetchDescriptor<Skill>())
        let artifactGate = try XCTUnwrap(skills.first(where: { $0.name == "artifact-handoff-gate" }))
        let refreshedAgents = try context.fetch(FetchDescriptor<Agent>())

        XCTAssertTrue(artifactGate.content.contains("Drafts belong in chat + blackboard first"))
        XCTAssertTrue(try XCTUnwrap(refreshedAgents.first(where: { $0.name == "Orchestrator" })).skillIds.contains(artifactGate.id))
        XCTAssertTrue(try XCTUnwrap(refreshedAgents.first(where: { $0.name == "Designer" })).skillIds.contains(artifactGate.id))
        XCTAssertTrue(try XCTUnwrap(refreshedAgents.first(where: { $0.name == "Tester" })).skillIds.contains(artifactGate.id))
    }

    func testLabelUsesDownloadedManagedPathModelName() throws {
        let tempDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDataDirectory) }

        AppSettings.store.set(tempDataDirectory.path, forKey: AppSettings.dataDirectoryKey)

        let downloadDirectory = LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: tempDataDirectory.path)
        let manifestURL = URL(fileURLWithPath: LocalProviderInstaller.managedMLXManifestPath(dataDirectoryPath: tempDataDirectory.path))
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let managedPath = URL(fileURLWithPath: downloadDirectory)
            .appendingPathComponent("archive/custom-qwen", isDirectory: true)
        try FileManager.default.createDirectory(at: managedPath, withIntermediateDirectories: true)

        let manifest = ManagedInstalledMLXManifest(installed: [
            ManagedInstalledMLXModel(
                modelIdentifier: "archive/custom-qwen",
                downloadDirectory: downloadDirectory,
                installedAt: Date(),
                sourceURL: "https://example.com/custom-qwen.tar.gz",
                managedPath: managedPath.path
            )
        ])
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        XCTAssertEqual(AgentDefaults.label(for: managedPath.path), "custom qwen")
    }

    func testSessionOverrideTakesPrecedenceOverAgentAndSystemProviderDefaults() {
        AppSettings.store.set(ProviderSelection.claude.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(ClaudeModel.sonnet.rawValue, forKey: AppSettings.defaultClaudeModelKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        let agent = Agent(
            name: "Inherited Agent",
            provider: ProviderSelection.system.rawValue,
            model: AgentDefaults.inheritMarker
        )

        let effectiveProvider = AgentDefaults.resolveEffectiveProvider(
            sessionOverride: ProviderSelection.codex.rawValue,
            agentSelection: agent.provider
        )
        let effectiveModel = AgentDefaults.resolveEffectiveModel(
            sessionOverride: AgentDefaults.inheritMarker,
            agentSelection: agent.model,
            provider: effectiveProvider
        )

        XCTAssertEqual(effectiveProvider, ProviderSelection.codex.rawValue)
        XCTAssertEqual(effectiveModel, CodexModel.gpt5Codex.rawValue)
    }

    func testIncompatibleExplicitModelFallsBackToEffectiveProviderDefault() {
        AppSettings.store.set(ProviderSelection.codex.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        let agent = Agent(
            name: "Codex Agent",
            provider: ProviderSelection.codex.rawValue,
            model: ClaudeModel.opus.rawValue
        )
        let session = Session(agent: agent, workingDirectory: "/tmp")

        XCTAssertEqual(session.provider, ProviderSelection.codex.rawValue)
        XCTAssertEqual(session.model, CodexModel.gpt5Codex.rawValue)
    }

    func testSessionModelOverrideBeatsAgentModelWhenCompatible() {
        AppSettings.store.set(ProviderSelection.claude.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(ClaudeModel.sonnet.rawValue, forKey: AppSettings.defaultClaudeModelKey)

        let resolved = AgentDefaults.resolveEffectiveModel(
            sessionOverride: ClaudeModel.opus.rawValue,
            agentSelection: ClaudeModel.haiku.rawValue,
            provider: ProviderSelection.claude.rawValue
        )

        XCTAssertEqual(resolved, ClaudeModel.opus.rawValue)
    }

    func testSessionModelOverrideFallsBackWhenIncompatibleWithEffectiveProvider() {
        AppSettings.store.set(ProviderSelection.codex.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        let resolved = AgentDefaults.resolveEffectiveModel(
            sessionOverride: ClaudeModel.opus.rawValue,
            agentSelection: ClaudeModel.haiku.rawValue,
            provider: ProviderSelection.codex.rawValue
        )

        XCTAssertEqual(resolved, CodexModel.gpt5Codex.rawValue)
    }

    func testProvisionerUsesSessionEffectiveProviderAndModel() {
        AppSettings.store.set(ProviderSelection.claude.rawValue, forKey: AppSettings.defaultProviderKey)

        let agent = Agent(name: "Resolver", model: ClaudeModel.sonnet.rawValue)
        context.insert(agent)

        let session = Session(agent: agent, mission: "Ship it", workingDirectory: "/tmp/work")
        session.provider = ProviderSelection.codex.rawValue
        session.model = CodexModel.gpt5Codex.rawValue

        let provisioner = AgentProvisioner(modelContext: context)
        let config = provisioner.config(for: session)

        XCTAssertEqual(config?.provider, ProviderSelection.codex.rawValue)
        XCTAssertEqual(config?.model, CodexModel.gpt5Codex.rawValue)
        XCTAssertEqual(config?.workingDirectory, "/tmp/work")
    }

    func testFreeformConfigUsesResolvedProviderDisplayNameAndModel() {
        AppSettings.store.set(ProviderSelection.codex.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)

        let config = AgentDefaults.makeFreeformAgentConfig(
            provider: ProviderSelection.system.rawValue,
            model: AgentDefaults.inheritMarker,
            workingDirectory: "/tmp/freeform"
        )

        XCTAssertEqual(config.provider, ProviderSelection.codex.rawValue)
        XCTAssertEqual(config.name, "Codex")
        XCTAssertEqual(config.model, CodexModel.gpt5Codex.rawValue)
        XCTAssertEqual(config.workingDirectory, "/tmp/freeform")
    }

    func testProvisionerKeepsSkillsStructuredAndLeavesSystemPromptForBasePromptAndMission() {
        let skillA = Skill(name: "Plan Carefully", content: "Always plan before editing.")
        let skillB = Skill(name: "Review Output", content: "Double-check the final answer.")
        context.insert(skillA)
        context.insert(skillB)

        let agent = Agent(name: "Structured", systemPrompt: "Base identity prompt.")
        agent.skillIds = [skillA.id, skillB.id]
        context.insert(agent)

        let config = AgentProvisioner(modelContext: context).provision(agent: agent, mission: "Ship feature X").0

        XCTAssertEqual(config.skills.map(\.name), ["Plan Carefully", "Review Output"])
        XCTAssertEqual(config.systemPrompt, "Base identity prompt.\n\n# Current Mission\nShip feature X\n")
        XCTAssertFalse(config.systemPrompt.contains("Always plan before editing."))
        XCTAssertFalse(config.systemPrompt.contains("## Plan Carefully"))
    }

    func testProvisionerIncludesSkillLinkedMCPsAndDeduplicatesThem() {
        let argus = MCPServer(name: "Argus", transport: .stdio(command: "npx", args: ["-y", "argus-mcp"], env: [:]))
        let octocode = MCPServer(name: "Octocode", transport: .stdio(command: "npx", args: ["-y", "octocode-mcp"], env: [:]))
        let appXray = MCPServer(name: "AppXray", transport: .stdio(command: "npx", args: ["-y", "appxray-mcp"], env: [:]))
        [argus, octocode, appXray].forEach(context.insert)

        let reviewSkill = Skill(name: "Code Review", content: "Review carefully.")
        reviewSkill.mcpServerIds = [octocode.id, appXray.id]
        context.insert(reviewSkill)

        let agent = Agent(name: "Reviewer")
        agent.skillIds = [reviewSkill.id]
        agent.extraMCPServerIds = [argus.id, octocode.id]
        context.insert(agent)

        let config = AgentProvisioner(modelContext: context).provision(agent: agent, mission: nil).0

        XCTAssertEqual(config.mcpServers.map(\.name), ["Argus", "Octocode", "AppXray"])
    }

    func testProvisionerIgnoresDisabledSkillsAndDoesNotAddTheirMCPs() {
        let octocode = MCPServer(name: "Octocode", transport: .stdio(command: "npx", args: ["-y", "octocode-mcp"], env: [:]))
        context.insert(octocode)

        let disabledSkill = Skill(name: "Disabled Skill", content: "Should not be sent.")
        disabledSkill.isEnabled = false
        disabledSkill.mcpServerIds = [octocode.id]
        context.insert(disabledSkill)

        let agent = Agent(name: "DisabledSkillAgent")
        agent.skillIds = [disabledSkill.id]
        context.insert(agent)

        let config = AgentProvisioner(modelContext: context).provision(agent: agent, mission: nil).0

        XCTAssertTrue(config.skills.isEmpty)
        XCTAssertTrue(config.mcpServers.isEmpty)
        XCTAssertFalse(config.systemPrompt.contains("Should not be sent."))
    }

    func testPeerWireProviderDefaultsToSystemWhenMissing() throws {
        let data = """
        {
          "id":"DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF",
          "name":"PeerAgent",
          "agentDescription":"desc",
          "systemPrompt":"prompt",
          "model":"sonnet",
          "icon":"cpu",
          "color":"blue",
          "skillNames":[],
          "extraMCPNames":[]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WireAgentExport.self, from: data)
        XCTAssertEqual(decoded.provider, ProviderSelection.system.rawValue)
    }

    func testConfigDTOProviderDefaultsToSystemWhenMissing() throws {
        let data = """
        {
          "name":"ConfigAgent",
          "enabled":true,
          "agentDescription":"desc",
          "model":"sonnet",
          "icon":"cpu",
          "color":"blue",
          "skillNames":[],
          "mcpServerNames":[],
          "permissionSetName":"Full Access"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AgentConfigDTO.self, from: data)
        XCTAssertEqual(decoded.provider, ProviderSelection.system.rawValue)
    }

    func testResetAllClearsProviderAndPerProviderModelDefaults() {
        AppSettings.store.set(ProviderSelection.codex.rawValue, forKey: AppSettings.defaultProviderKey)
        AppSettings.store.set(ClaudeModel.haiku.rawValue, forKey: AppSettings.defaultClaudeModelKey)
        AppSettings.store.set(CodexModel.gpt5Codex.rawValue, forKey: AppSettings.defaultCodexModelKey)
        AppSettings.store.set(FoundationModel.system.rawValue, forKey: AppSettings.defaultFoundationModelKey)
        AppSettings.store.set("mlx-community/test-model", forKey: AppSettings.defaultMLXModelKey)
        AppSettings.store.set(42, forKey: AppSettings.defaultMaxTurnsKey)
        AppSettings.store.set(12.5, forKey: AppSettings.defaultMaxBudgetKey)

        AppSettings.resetAll()

        XCTAssertNil(AppSettings.store.string(forKey: AppSettings.defaultProviderKey))
        XCTAssertNil(AppSettings.store.string(forKey: AppSettings.defaultClaudeModelKey))
        XCTAssertNil(AppSettings.store.string(forKey: AppSettings.defaultCodexModelKey))
        XCTAssertNil(AppSettings.store.string(forKey: AppSettings.defaultFoundationModelKey))
        XCTAssertNil(AppSettings.store.string(forKey: AppSettings.defaultMLXModelKey))
        XCTAssertNil(AppSettings.store.object(forKey: AppSettings.defaultMaxTurnsKey))
        XCTAssertNil(AppSettings.store.object(forKey: AppSettings.defaultMaxBudgetKey))
    }

    func testModelsSettingsTabMetadataIsRegistered() {
        XCTAssertTrue(SettingsSection.allCases.contains(.models))
        XCTAssertEqual(SettingsSection.models.title, "Models")
        XCTAssertEqual(SettingsSection.models.xrayId, "settings.tab.models")
    }

    func testProvisionerResolvesExpectedMCPSetsForBuiltInRoles() {
        let argus = MCPServer(name: "Argus", transport: .stdio(command: "npx", args: ["-y", "-p", "@wix/argus", "argus-mcp"], env: [:]))
        let appXray = MCPServer(name: "AppXray", transport: .stdio(command: "npx", args: ["-y", "@wix/appxray-mcp-server"], env: ["APPXRAY_AUTO_CONNECT": "true"]))
        let octocode = MCPServer(name: "Octocode", transport: .stdio(command: "npx", args: ["-y", "octocode-mcp@latest"], env: [:]))
        [argus, appXray, octocode].forEach(context.insert)

        let coder = Agent(name: "Coder")
        coder.extraMCPServerIds = [argus.id, appXray.id, octocode.id]
        let tester = Agent(name: "Tester")
        tester.extraMCPServerIds = [argus.id, appXray.id, octocode.id]
        let reviewer = Agent(name: "Reviewer")
        reviewer.extraMCPServerIds = [octocode.id]
        let devOps = Agent(name: "DevOps")
        devOps.extraMCPServerIds = []
        [coder, tester, reviewer, devOps].forEach(context.insert)

        let provisioner = AgentProvisioner(modelContext: context)

        XCTAssertEqual(Set(provisioner.provision(agent: coder, mission: nil).0.mcpServers.map(\.name)), Set(["Argus", "AppXray", "Octocode"]))
        XCTAssertEqual(Set(provisioner.provision(agent: tester, mission: nil).0.mcpServers.map(\.name)), Set(["Argus", "AppXray", "Octocode"]))
        XCTAssertEqual(provisioner.provision(agent: reviewer, mission: nil).0.mcpServers.map(\.name), ["Octocode"])
        XCTAssertTrue(provisioner.provision(agent: devOps, mission: nil).0.mcpServers.isEmpty)
    }

    func testProvisionerSkipsHeavyAmbientMCPsForLocalProviders() {
        let argus = MCPServer(name: "Argus", transport: .stdio(command: "node", args: ["argus.js"], env: [:]))
        let appXray = MCPServer(name: "AppXray", transport: .stdio(command: "node", args: ["appxray.js"], env: [:]))
        let octocode = MCPServer(name: "Octocode", transport: .stdio(command: "npx", args: ["-y", "octocode-mcp@latest"], env: [:]))
        let blackboard = MCPServer(name: "Blackboard", transport: .stdio(command: "node", args: ["blackboard.js"], env: [:]))
        [argus, appXray, octocode, blackboard].forEach(context.insert)

        let agent = Agent(name: "Local Coder")
        agent.extraMCPServerIds = [argus.id, appXray.id, octocode.id, blackboard.id]
        context.insert(agent)

        let session = Session(agent: agent, mission: nil, workingDirectory: "/tmp/work")
        session.provider = ProviderSelection.mlx.rawValue

        let config = AgentProvisioner(modelContext: context).config(for: session)

        XCTAssertEqual(config?.mcpServers.map(\.name), ["Blackboard"])
    }

    func testProvisionerDoesNotInjectPeerBusToolNamesIntoAllowedTools() {
        let permissions = PermissionSet(name: "Locked", allowRules: ["Read", "Grep"], permissionMode: "acceptEdits")
        context.insert(permissions)

        let agent = Agent(name: "Coder")
        agent.permissionSetId = permissions.id
        context.insert(agent)

        let config = AgentProvisioner(modelContext: context).provision(agent: agent, mission: nil).0

        XCTAssertEqual(config.allowedTools, ["Read", "Grep"])
        XCTAssertFalse(config.allowedTools.contains("peer_chat_start"))
        XCTAssertFalse(config.allowedTools.contains("blackboard_read"))
        XCTAssertFalse(config.allowedTools.contains("ask_user"))
    }

    func testConfigSyncMigratesBuiltInCoderMCPDefaultsWithoutClobberingExistingMCPs() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        try ConfigFileManager.createDirectoryStructure()

        try ConfigFileManager.writeMCP(
            MCPConfigDTO(
                name: "Argus",
                enabled: true,
                serverDescription: "UI automation",
                transportKind: "stdio",
                transportCommand: "npx",
                transportArgs: ["-y", "@anthropic-ai/argus-mcp-server"],
                transportEnv: [:],
                transportUrl: nil,
                transportHeaders: nil
            ),
            slug: "argus"
        )
        try ConfigFileManager.writeMCP(
            MCPConfigDTO(
                name: "AppXray",
                enabled: true,
                serverDescription: "Runtime inspection",
                transportKind: "stdio",
                transportCommand: "npx",
                transportArgs: ["-y", "@anthropic-ai/appxray-mcp-server"],
                transportEnv: [:],
                transportUrl: nil,
                transportHeaders: nil
            ),
            slug: "appxray"
        )
        try ConfigFileManager.writeMCP(
            MCPConfigDTO(
                name: "Octocode",
                enabled: true,
                serverDescription: "Semantic code research",
                transportKind: "stdio",
                transportCommand: "npx",
                transportArgs: ["-y", "octocode-mcp@latest"],
                transportEnv: [:],
                transportUrl: nil,
                transportHeaders: nil
            ),
            slug: "octocode"
        )
        try ConfigFileManager.writeMCP(
            MCPConfigDTO(
                name: "Custom Debugger",
                enabled: true,
                serverDescription: "Custom debugger",
                transportKind: "stdio",
                transportCommand: "custom-debugger",
                transportArgs: [],
                transportEnv: [:],
                transportUrl: nil,
                transportHeaders: nil
            ),
            slug: "custom-debugger"
        )

        try ConfigFileManager.writePermission(
            PermissionConfigDTO(name: "Full Access", enabled: true, allowRules: [], denyRules: [], additionalDirectories: [], permissionMode: "allowlist"),
            slug: "full-access"
        )
        try ConfigFileManager.writePermission(
            PermissionConfigDTO(name: "Read Only", enabled: true, allowRules: [], denyRules: [], additionalDirectories: [], permissionMode: "allowlist"),
            slug: "read-only"
        )
        try ConfigFileManager.writePermission(
            PermissionConfigDTO(name: "Git Only", enabled: true, allowRules: [], denyRules: [], additionalDirectories: [], permissionMode: "allowlist"),
            slug: "git-only"
        )

        try ConfigFileManager.writeAgent(
            AgentConfigDTO(
                name: "Coder",
                enabled: true,
                agentDescription: "desc",
                provider: ProviderSelection.system.rawValue,
                model: "opus",
                icon: "cpu",
                color: "blue",
                skillNames: [],
                mcpServerNames: ["Custom Debugger"],
                permissionSetName: "Full Access",
                systemPromptTemplate: nil,
                systemPromptVariables: nil,
                maxTurns: 50,
                maxBudget: 5,
                maxThinkingTokens: nil,
                defaultWorkingDirectory: nil
            ),
            slug: "coder"
        )
        try ConfigFileManager.writeAgent(
            AgentConfigDTO(
                name: "Tester",
                enabled: true,
                agentDescription: "desc",
                provider: ProviderSelection.system.rawValue,
                model: "sonnet",
                icon: "checkmark",
                color: "teal",
                skillNames: [],
                mcpServerNames: ["Argus", "AppXray"],
                permissionSetName: "Full Access",
                systemPromptTemplate: nil,
                systemPromptVariables: nil,
                maxTurns: 50,
                maxBudget: 5,
                maxThinkingTokens: nil,
                defaultWorkingDirectory: nil
            ),
            slug: "tester"
        )
        try ConfigFileManager.writeAgent(
            AgentConfigDTO(
                name: "Reviewer",
                enabled: true,
                agentDescription: "desc",
                provider: ProviderSelection.system.rawValue,
                model: "sonnet",
                icon: "eye",
                color: "orange",
                skillNames: [],
                mcpServerNames: ["GitHub"],
                permissionSetName: "Read Only",
                systemPromptTemplate: nil,
                systemPromptVariables: nil,
                maxTurns: 30,
                maxBudget: 3,
                maxThinkingTokens: nil,
                defaultWorkingDirectory: nil
            ),
            slug: "reviewer"
        )
        try ConfigFileManager.writeAgent(
            AgentConfigDTO(
                name: "DevOps",
                enabled: true,
                agentDescription: "desc",
                provider: ProviderSelection.system.rawValue,
                model: "haiku",
                icon: "gear",
                color: "gray",
                skillNames: [],
                mcpServerNames: ["GitHub"],
                permissionSetName: "Git Only",
                systemPromptTemplate: nil,
                systemPromptVariables: nil,
                maxTurns: 30,
                maxBudget: 1,
                maxThinkingTokens: nil,
                defaultWorkingDirectory: nil
            ),
            slug: "devops"
        )

        let syncService = ConfigSyncService()
        syncService.start(container: container)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let coderFile = try XCTUnwrap(
            ConfigFileManager.readAllAgents().first(where: { $0.slug == "coder" })?.dto
        )
        XCTAssertEqual(coderFile.mcpServerNames, ["Custom Debugger", "Argus", "AppXray", "Octocode"])

        let testerFile = try XCTUnwrap(
            ConfigFileManager.readAllAgents().first(where: { $0.slug == "tester" })?.dto
        )
        XCTAssertEqual(testerFile.mcpServerNames, ["Argus", "AppXray", "Octocode"])

        let reviewerFile = try XCTUnwrap(
            ConfigFileManager.readAllAgents().first(where: { $0.slug == "reviewer" })?.dto
        )
        XCTAssertEqual(reviewerFile.mcpServerNames, ["Octocode"])

        let devOpsFile = try XCTUnwrap(
            ConfigFileManager.readAllAgents().first(where: { $0.slug == "devops" })?.dto
        )
        XCTAssertEqual(devOpsFile.mcpServerNames, [])

        let agents = try context.fetch(FetchDescriptor<Agent>())
        let coder = try XCTUnwrap(agents.first(where: { $0.configSlug == "coder" }))
        let allMCPs = try context.fetch(FetchDescriptor<MCPServer>())
        let mcpById = Dictionary(uniqueKeysWithValues: allMCPs.map { ($0.id, $0.name) })
        let coderMCPNames = coder.extraMCPServerIds.compactMap { mcpById[$0] }
        XCTAssertEqual(coderMCPNames, ["Custom Debugger", "Argus", "AppXray", "Octocode"])

        let argusFile = try XCTUnwrap(
            ConfigFileManager.readAllMCPs().first(where: { $0.slug == "argus" })?.dto
        )
        let expectedArgusTransport = try XCTUnwrap(ConfigSyncService.builtInTransportSpec(for: "argus"))
        XCTAssertEqual(argusFile.transportCommand, expectedArgusTransport.command)
        XCTAssertEqual(argusFile.transportArgs, expectedArgusTransport.args)
        XCTAssertEqual(argusFile.transportEnv ?? [:], expectedArgusTransport.env)

        let appXrayFile = try XCTUnwrap(
            ConfigFileManager.readAllMCPs().first(where: { $0.slug == "appxray" })?.dto
        )
        let expectedAppXrayTransport = try XCTUnwrap(ConfigSyncService.builtInTransportSpec(for: "appxray"))
        XCTAssertEqual(appXrayFile.transportCommand, expectedAppXrayTransport.command)
        XCTAssertEqual(appXrayFile.transportArgs, expectedAppXrayTransport.args)
        XCTAssertEqual(appXrayFile.transportEnv ?? [:], expectedAppXrayTransport.env)
    }

    func testEnsureBundleMCPsPresentCopiesMissingOctocodeConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        try ConfigFileManager.createDirectoryStructure()

        let argusTarget = tempDir.appendingPathComponent("config/mcps/argus.json")
        let appXrayTarget = tempDir.appendingPathComponent("config/mcps/appxray.json")
        let sentryTarget = tempDir.appendingPathComponent("config/mcps/sentry.json")
        let octocodeTarget = tempDir.appendingPathComponent("config/mcps/octocode.json")

        try ConfigFileManager.writeMCP(
            MCPConfigDTO(
                name: "Argus",
                enabled: true,
                serverDescription: "UI automation",
                transportKind: "stdio",
                transportCommand: "npx",
                transportArgs: ["-y", "-p", "@wix/argus", "argus-mcp"],
                transportEnv: [:],
                transportUrl: nil,
                transportHeaders: nil
            ),
            slug: "argus"
        )
        try ConfigFileManager.writeMCP(
            MCPConfigDTO(
                name: "AppXray",
                enabled: true,
                serverDescription: "Runtime inspection",
                transportKind: "stdio",
                transportCommand: "npx",
                transportArgs: ["-y", "@wix/appxray-mcp-server"],
                transportEnv: ["APPXRAY_AUTO_CONNECT": "true"],
                transportUrl: nil,
                transportHeaders: nil
            ),
            slug: "appxray"
        )
        try ConfigFileManager.writeMCP(
            MCPConfigDTO(
                name: "Sentry",
                enabled: true,
                serverDescription: "Error monitoring",
                transportKind: "http",
                transportCommand: nil,
                transportArgs: nil,
                transportEnv: nil,
                transportUrl: "https://mcp.sentry.dev/sse",
                transportHeaders: ["Authorization": "Bearer ${SENTRY_AUTH_TOKEN}"]
            ),
            slug: "sentry"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: octocodeTarget.path))

        ConfigFileManager.ensureBundleMCPsPresent()

        XCTAssertTrue(FileManager.default.fileExists(atPath: argusTarget.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appXrayTarget.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentryTarget.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: octocodeTarget.path))

        let copied = try XCTUnwrap(
            ConfigFileManager.readAllMCPs().first(where: { $0.slug == "octocode" })?.dto
        )
        XCTAssertEqual(copied.name, "Octocode")
        XCTAssertEqual(copied.transportKind, "stdio")
        XCTAssertEqual(copied.transportCommand, "npx")
        XCTAssertEqual(copied.transportArgs, ["-y", "octocode-mcp@latest"])

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testConfigSyncRemovesRetiredGitHubMCPConfigOnStart() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        try ConfigFileManager.createDirectoryStructure()

        let gitHubTarget = tempDir.appendingPathComponent("config/mcps/github.json")
        try ConfigFileManager.writeMCP(
            MCPConfigDTO(
                name: "GitHub",
                enabled: true,
                serverDescription: "GitHub integration",
                transportKind: "stdio",
                transportCommand: "npx",
                transportArgs: ["-y", "@modelcontextprotocol/server-github"],
                transportEnv: [:],
                transportUrl: nil,
                transportHeaders: nil
            ),
            slug: "github"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: gitHubTarget.path))

        let syncService = ConfigSyncService()
        syncService.start(container: container)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: gitHubTarget.path))
    }
}
