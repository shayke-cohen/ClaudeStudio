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
}
