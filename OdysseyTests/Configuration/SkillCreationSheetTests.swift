import XCTest
import SwiftData
@testable import Odyssey

final class SkillCreationSheetTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([Skill.self, MCPServer.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    func test_saveWritesMarkdownFileWithFrontmatter() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-skill-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        try performSkillSave(
            existingSkill: nil,
            name: "Security Patterns",
            skillDescription: "Teaches security vulnerability patterns",
            category: "Security",
            triggers: ["security", "vulnerability"],
            mcpServerIds: [],
            content: "# Security Patterns\n\nCheck for injection risks.",
            version: "1.0",
            context: context
        )

        let expectedFile = tempDir.appendingPathComponent("config/skills/security-patterns.md")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedFile.path),
            "Expected file at \(expectedFile.path)"
        )

        let skills = try context.fetch(FetchDescriptor<Skill>())
        XCTAssertEqual(skills.count, 1, "Expected exactly one Skill in SwiftData")
        XCTAssertEqual(skills.first?.name, "Security Patterns")
        XCTAssertEqual(skills.first?.configSlug, "security-patterns")
        XCTAssertEqual(skills.first?.category, "Security")
        XCTAssertEqual(skills.first?.triggers, ["security", "vulnerability"])
    }

    func test_saveUpdatesExistingSkill() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-skill-test-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        // Create initial skill
        let existing = Skill(name: "Old Name", skillDescription: "Old desc", category: "General", content: "old")
        context.insert(existing)
        try context.save()

        // Update via performSkillSave
        try performSkillSave(
            existingSkill: existing,
            name: "Updated Name",
            skillDescription: "New desc",
            category: "Testing",
            triggers: ["test"],
            mcpServerIds: [],
            content: "# Updated",
            version: "2.0",
            context: context
        )

        let skills = try context.fetch(FetchDescriptor<Skill>())
        // Still only one skill (updated in place)
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills.first?.name, "Updated Name")
        XCTAssertEqual(skills.first?.category, "Testing")
        XCTAssertEqual(skills.first?.version, "2.0")

        let expectedFile = tempDir.appendingPathComponent("config/skills/updated-name.md")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedFile.path),
            "Expected file at \(expectedFile.path)"
        )
    }

    func test_saveWithMCPIds_persistsMCPIdsInSwiftData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-skill-mcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        let mcp1 = MCPServer(name: "GitHub MCP", serverDescription: "GitHub tools", transport: .stdio(command: "gh", args: [], env: [:]))
        let mcp2 = MCPServer(name: "Filesystem MCP", serverDescription: "File tools", transport: .stdio(command: "fs", args: [], env: [:]))
        context.insert(mcp1)
        context.insert(mcp2)
        try context.save()

        try performSkillSave(
            existingSkill: nil,
            name: "Security Skill",
            skillDescription: "Security patterns",
            category: "Security",
            triggers: ["security"],
            mcpServerIds: [mcp1.id, mcp2.id],
            content: "# Security\nBe careful.",
            version: "1.0",
            context: context
        )

        let skills = try context.fetch(FetchDescriptor<Skill>())
        let saved = try XCTUnwrap(skills.first)
        XCTAssertEqual(Set(saved.mcpServerIds), Set([mcp1.id, mcp2.id]))
    }

    func test_saveWithEmptyMCPIds_persistsEmptyArray() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-skill-nomcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        try performSkillSave(
            existingSkill: nil,
            name: "Solo Skill",
            skillDescription: "",
            category: "General",
            triggers: [],
            mcpServerIds: [],
            content: "No MCPs needed.",
            version: "1.0",
            context: context
        )

        let skills = try context.fetch(FetchDescriptor<Skill>())
        XCTAssertEqual(skills.first?.mcpServerIds, [])
    }

    func test_slugify_handlesSpecialCharacters() {
        XCTAssertEqual(ConfigFileManager.slugify("Security Patterns"), "security-patterns")
        XCTAssertEqual(ConfigFileManager.slugify("Code Review Style!"), "code-review-style")
    }

    func test_saveWritesFileContent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-skill-test-content-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        let bodyContent = "# Architecture Principles\n\nPrefer simple over clever."

        try performSkillSave(
            existingSkill: nil,
            name: "Architecture Principles",
            skillDescription: "Core architecture guidelines",
            category: "Architecture",
            triggers: ["arch", "design"],
            mcpServerIds: [],
            content: bodyContent,
            version: "1.0",
            context: context
        )

        let expectedFile = tempDir.appendingPathComponent("config/skills/architecture-principles.md")
        let fileContents = try String(contentsOf: expectedFile, encoding: .utf8)

        // File should contain YAML frontmatter
        XCTAssertTrue(fileContents.contains("---"), "File should contain YAML frontmatter delimiters")
        XCTAssertTrue(fileContents.contains("Architecture Principles"), "File should contain the skill name")
        // File should contain the body content
        XCTAssertTrue(fileContents.contains(bodyContent), "File should contain the body content")
    }
}
