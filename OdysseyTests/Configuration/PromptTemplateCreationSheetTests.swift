import XCTest
import SwiftData
@testable import Odyssey

final class PromptTemplateCreationSheetTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([Agent.self, AgentGroup.self, PromptTemplate.self, Skill.self, MCPServer.self, PermissionSet.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    func test_saveWritesTemplateFileAndInsertsSwiftData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-tmpl-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        let agent = Agent(name: "Coder")
        agent.configSlug = "coder"
        context.insert(agent)
        try? context.save()

        let saved = try performTemplateSave(
            existingTemplate: nil,
            name: "Review PR",
            prompt: "Review the pull request for issues.",
            ownerAgent: agent,
            ownerGroup: nil,
            sortOrder: 0,
            context: context
        )

        // Verify the .md file was written on disk
        let expectedDir = tempDir.appendingPathComponent("config/prompt-templates/agents/coder/")
        let files = try FileManager.default.contentsOfDirectory(atPath: expectedDir.path)
        XCTAssertFalse(files.isEmpty, "Expected template file in \(expectedDir.path)")
        XCTAssertTrue(files.contains(where: { $0.hasSuffix(".md") }), "Expected a .md file in \(expectedDir.path)")

        // Verify SwiftData record was inserted
        let templates = try context.fetch(FetchDescriptor<PromptTemplate>())
        XCTAssertEqual(templates.count, 1, "Expected exactly one PromptTemplate in SwiftData")
        XCTAssertEqual(templates.first?.name, "Review PR")
        XCTAssertEqual(templates.first?.prompt, "Review the pull request for issues.")

        // Verify return value
        XCTAssertEqual(saved.name, "Review PR")
        XCTAssertNotNil(saved.configSlug)
        XCTAssertTrue(saved.configSlug?.hasPrefix("agents/coder/") == true, "configSlug should start with agents/coder/")
    }

    func test_saveWithGroupOwner() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-tmpl-group-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        let group = AgentGroup(name: "Security Team")
        group.configSlug = "security-team"
        context.insert(group)
        try? context.save()

        try performTemplateSave(
            existingTemplate: nil,
            name: "Full Audit",
            prompt: "Perform a full security audit of the codebase.",
            ownerAgent: nil,
            ownerGroup: group,
            sortOrder: 1,
            context: context
        )

        let expectedDir = tempDir.appendingPathComponent("config/prompt-templates/groups/security-team/")
        let files = try FileManager.default.contentsOfDirectory(atPath: expectedDir.path)
        XCTAssertFalse(files.isEmpty, "Expected template file in \(expectedDir.path)")

        let templates = try context.fetch(FetchDescriptor<PromptTemplate>())
        XCTAssertEqual(templates.first?.name, "Full Audit")
        XCTAssertEqual(templates.first?.sortOrder, 1)
    }

    func test_updateExistingTemplate() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-tmpl-update-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        setenv("ODYSSEY_DATA_DIR", tempDir.path, 1)
        defer { unsetenv("ODYSSEY_DATA_DIR") }

        let agent = Agent(name: "Reviewer")
        agent.configSlug = "reviewer"
        context.insert(agent)

        let existing = PromptTemplate(
            name: "Old Name",
            prompt: "Old prompt.",
            sortOrder: 2,
            isBuiltin: false,
            agent: agent,
            configSlug: "agents/reviewer/old-name"
        )
        context.insert(existing)
        try? context.save()

        let updated = try performTemplateSave(
            existingTemplate: existing,
            name: "New Name",
            prompt: "New prompt content.",
            ownerAgent: agent,
            ownerGroup: nil,
            sortOrder: 2,
            context: context
        )

        XCTAssertEqual(updated.name, "New Name")
        XCTAssertEqual(updated.prompt, "New prompt content.")
        // Should be the same object
        XCTAssertEqual(updated.id, existing.id)

        // SwiftData should not have duplicated the record
        let templates = try context.fetch(FetchDescriptor<PromptTemplate>())
        XCTAssertEqual(templates.count, 1, "Update should not create a duplicate record")
    }
}
