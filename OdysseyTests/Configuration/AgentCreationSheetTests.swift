import XCTest
import SwiftData
@testable import Odyssey

final class AgentCreationSheetTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([Agent.self, Skill.self, MCPServer.self, PermissionSet.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    func test_slugify_kebabCasesName() {
        XCTAssertEqual(ConfigFileManager.slugify("Security Reviewer"), "security-reviewer")
        XCTAssertEqual(ConfigFileManager.slugify("My Agent!"), "my-agent")
    }

    func test_saveCreatesFileAndInsertsSwiftData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-agent-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        var savedAgent: Agent? = nil

        try performAgentSave(
            name: "Test Agent",
            agentDescription: "A test agent",
            icon: "cpu",
            color: "blue",
            provider: ProviderSelection.system.rawValue,
            model: AgentDefaults.inheritMarker,
            systemPrompt: "You are a test agent.",
            maxTurns: nil,
            maxBudget: nil,
            instancePolicy: .agentDefault,
            modelContext: context,
            onSave: { savedAgent = $0 },
            dismiss: {}
        )

        // Verify config.json was written inside agents/test-agent/
        let expectedFile = tempDir
            .appendingPathComponent("config/agents/test-agent/config.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedFile.path),
            "Expected config.json at \(expectedFile.path)"
        )

        // Verify prompt.md was also written
        let expectedPrompt = tempDir
            .appendingPathComponent("config/agents/test-agent/prompt.md")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedPrompt.path),
            "Expected prompt.md at \(expectedPrompt.path)"
        )

        // Verify the Agent was inserted into SwiftData
        let agents = try context.fetch(FetchDescriptor<Agent>())
        XCTAssertEqual(agents.count, 1, "Expected exactly one Agent in SwiftData")
        XCTAssertEqual(agents.first?.name, "Test Agent")
        XCTAssertEqual(agents.first?.configSlug, "test-agent")

        // Verify onSave callback received the new agent
        XCTAssertNotNil(savedAgent)
        XCTAssertEqual(savedAgent?.name, "Test Agent")
    }

    func test_saveUpdatesExistingAgent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-agent-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        // Insert an existing agent into SwiftData
        let existing = Agent(
            name: "Old Name",
            agentDescription: "Old description",
            systemPrompt: "Old prompt",
            provider: ProviderSelection.system.rawValue,
            model: AgentDefaults.inheritMarker,
            icon: "star",
            color: "red"
        )
        context.insert(existing)
        try? context.save()

        try performAgentSave(
            existingAgent: existing,
            name: "New Name",
            agentDescription: "New description",
            icon: "bolt",
            color: "green",
            provider: ProviderSelection.system.rawValue,
            model: AgentDefaults.inheritMarker,
            systemPrompt: "New prompt.",
            maxTurns: nil,
            maxBudget: nil,
            instancePolicy: .agentDefault,
            modelContext: context,
            onSave: { _ in },
            dismiss: {}
        )

        // Should still have exactly 1 agent (no duplicate inserted)
        let agents = try context.fetch(FetchDescriptor<Agent>())
        XCTAssertEqual(agents.count, 1, "Expected exactly one Agent in SwiftData after update")

        // That agent should reflect the new values
        let updated = try XCTUnwrap(agents.first)
        XCTAssertEqual(updated.name, "New Name")
        XCTAssertEqual(updated.agentDescription, "New description")
        XCTAssertEqual(updated.icon, "bolt")
        XCTAssertEqual(updated.color, "green")

        // Config file should exist at the new slug path
        let newSlug = ConfigFileManager.slugify("New Name")
        let expectedFile = tempDir
            .appendingPathComponent("config/agents/\(newSlug)/config.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedFile.path),
            "Expected config.json at \(expectedFile.path)"
        )
    }

    func test_saveWithSystemProvider_omitsProviderFromConfigFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-agent-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        try performAgentSave(
            name: "Provider Test Agent",
            agentDescription: "Testing provider omission",
            icon: "cpu",
            color: "blue",
            provider: ProviderSelection.system.rawValue,
            model: AgentDefaults.inheritMarker,
            systemPrompt: "You are a test agent.",
            maxTurns: nil,
            maxBudget: nil,
            instancePolicy: .agentDefault,
            modelContext: context,
            onSave: { _ in },
            dismiss: {}
        )

        let slug = ConfigFileManager.slugify("Provider Test Agent")
        let configFile = tempDir
            .appendingPathComponent("config/agents/\(slug)/config.json")

        let contents = try String(contentsOf: configFile, encoding: .utf8)
        let data = Data(contents.utf8)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "config.json is not a JSON object"
        )

        // When provider is "system", the DTO should have provider = nil,
        // meaning the key is either absent or null in the serialised output.
        if let providerValue = json["provider"] {
            // Key present — value must be NSNull (i.e. JSON null)
            XCTAssertTrue(
                providerValue is NSNull,
                "Expected 'provider' to be null when system provider is selected, got \(providerValue)"
            )
        }
        // If the key is absent that is also acceptable — no further assertion needed.
    }

    func test_saveWithSkills_writesSkillSlugsToConfigAndSetsSwiftDataIds() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-agent-skill-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        // Insert two skills with known slugs
        let skill1 = Skill(name: "Code Review Style", skillDescription: "", category: "General", content: "")
        skill1.configSlug = "code-review-style"
        let skill2 = Skill(name: "Security Patterns", skillDescription: "", category: "Security", content: "")
        skill2.configSlug = "security-patterns"
        context.insert(skill1)
        context.insert(skill2)
        try context.save()

        var savedAgent: Agent? = nil
        try performAgentSave(
            name: "Skilled Agent",
            agentDescription: "",
            icon: "cpu",
            color: "blue",
            provider: ProviderSelection.system.rawValue,
            model: AgentDefaults.inheritMarker,
            systemPrompt: "",
            maxTurns: nil,
            maxBudget: nil,
            instancePolicy: .agentDefault,
            skillIds: [skill1.id, skill2.id],
            mcpIds: [],
            modelContext: context,
            onSave: { savedAgent = $0 },
            dismiss: {}
        )

        // Verify SwiftData agent has the skill IDs
        XCTAssertEqual(Set(savedAgent?.skillIds ?? []), Set([skill1.id, skill2.id]))

        // Verify config.json contains both skill slugs
        let slug = ConfigFileManager.slugify("Skilled Agent")
        let configFile = tempDir.appendingPathComponent("config/agents/\(slug)/config.json")
        let data = try Data(contentsOf: configFile)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let skills = try XCTUnwrap(json["skills"] as? [String])
        XCTAssertTrue(skills.contains("code-review-style"), "Expected code-review-style in skills")
        XCTAssertTrue(skills.contains("security-patterns"), "Expected security-patterns in skills")
    }

    func test_saveWithMCPs_writesMCPSlugsToConfigAndSetsSwiftDataIds() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-agent-mcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        let mcp = MCPServer(name: "GitHub MCP", serverDescription: "GitHub tools", transport: .stdio(command: "gh", args: [], env: [:]))
        mcp.configSlug = "github-mcp"
        context.insert(mcp)
        try context.save()

        var savedAgent: Agent? = nil
        try performAgentSave(
            name: "MCP Agent",
            agentDescription: "",
            icon: "cpu",
            color: "blue",
            provider: ProviderSelection.system.rawValue,
            model: AgentDefaults.inheritMarker,
            systemPrompt: "",
            maxTurns: nil,
            maxBudget: nil,
            instancePolicy: .agentDefault,
            skillIds: [],
            mcpIds: [mcp.id],
            modelContext: context,
            onSave: { savedAgent = $0 },
            dismiss: {}
        )

        XCTAssertEqual(savedAgent?.extraMCPServerIds, [mcp.id])

        let slug = ConfigFileManager.slugify("MCP Agent")
        let configFile = tempDir.appendingPathComponent("config/agents/\(slug)/config.json")
        let data = try Data(contentsOf: configFile)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let mcps = try XCTUnwrap(json["mcps"] as? [String])
        XCTAssertTrue(mcps.contains("github-mcp"), "Expected github-mcp in mcps")
    }

    func test_saveWithNoSkillsOrMCPs_writesEmptyArrays() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-agent-empty-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        try performAgentSave(
            name: "Plain Agent",
            agentDescription: "",
            icon: "cpu",
            color: "blue",
            provider: ProviderSelection.system.rawValue,
            model: AgentDefaults.inheritMarker,
            systemPrompt: "",
            maxTurns: nil,
            maxBudget: nil,
            instancePolicy: .agentDefault,
            modelContext: context,
            onSave: { _ in },
            dismiss: {}
        )

        let slug = ConfigFileManager.slugify("Plain Agent")
        let configFile = tempDir.appendingPathComponent("config/agents/\(slug)/config.json")
        let data = try Data(contentsOf: configFile)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let skills = try XCTUnwrap(json["skills"] as? [String])
        let mcps = try XCTUnwrap(json["mcps"] as? [String])
        XCTAssertTrue(skills.isEmpty, "Expected empty skills array")
        XCTAssertTrue(mcps.isEmpty, "Expected empty mcps array")
    }

    func test_saveThrowsOnInvalidPath() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-agent-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a FILE at the location where the config directory would be written,
        // so that any attempt to create a directory or write a file there must fail.
        let blockingFile = tempDir.appendingPathComponent("config")
        try "blocking".write(to: blockingFile, atomically: true, encoding: .utf8)

        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        XCTAssertThrowsError(
            try performAgentSave(
                name: "Throw Test Agent",
                agentDescription: "Should throw",
                icon: "cpu",
                color: "blue",
                provider: ProviderSelection.system.rawValue,
                model: AgentDefaults.inheritMarker,
                systemPrompt: "You are a test agent.",
                maxTurns: nil,
                maxBudget: nil,
                instancePolicy: .agentDefault,
                modelContext: context,
                onSave: { _ in },
                dismiss: {}
            ),
            "Expected performAgentSave to throw when ODYSSEY_DATA_DIR/config is a file, not a directory"
        )
    }
}
