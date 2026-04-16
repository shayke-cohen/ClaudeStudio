import Foundation
import SwiftData
import XCTest
@testable import Odyssey

/// Unit tests for the PromptTemplate SwiftData model and its on-disk
/// markdown + frontmatter format.
@MainActor
final class PromptTemplateTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for:
                Agent.self, AgentGroup.self, Session.self, Skill.self, MCPServer.self,
                PermissionSet.self, PromptTemplate.self, TaskItem.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Model

    func testPromptTemplate_defaults() {
        let template = PromptTemplate(name: "Review PR", prompt: "Review PR #___")
        XCTAssertEqual(template.name, "Review PR")
        XCTAssertEqual(template.prompt, "Review PR #___")
        XCTAssertEqual(template.sortOrder, 0)
        XCTAssertFalse(template.isBuiltin)
        XCTAssertNil(template.agent)
        XCTAssertNil(template.group)
        XCTAssertNil(template.ownerKind)
    }

    func testPromptTemplate_agentOwnership() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)
        let template = PromptTemplate(
            name: "Review PR", prompt: "Review PR #___",
            sortOrder: 1, isBuiltin: true, agent: agent,
            configSlug: "agents/coder/review-pr"
        )
        context.insert(template)
        try context.save()

        XCTAssertEqual(template.ownerKind, .agent)
        XCTAssertEqual(template.ownerSlugComponent, "coder")
        XCTAssertEqual(template.templateSlugComponent, "review-pr")
        XCTAssertEqual(agent.promptTemplates.count, 1)
        XCTAssertEqual(agent.promptTemplates.first?.name, "Review PR")
    }

    func testPromptTemplate_cascadeDeleteWhenAgentRemoved() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)
        let a = PromptTemplate(name: "A", prompt: "A body", agent: agent, configSlug: "agents/coder/a")
        let b = PromptTemplate(name: "B", prompt: "B body", agent: agent, configSlug: "agents/coder/b")
        context.insert(a)
        context.insert(b)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PromptTemplate>()), 2)

        context.delete(agent)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PromptTemplate>()), 0)
    }

    func testPromptTemplate_cascadeDeleteWhenGroupRemoved() throws {
        let group = AgentGroup(name: "Security Audit")
        context.insert(group)
        let t = PromptTemplate(
            name: "Full audit", prompt: "Do the audit",
            group: group, configSlug: "groups/security-audit/full-codebase-audit"
        )
        context.insert(t)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PromptTemplate>()), 1)

        context.delete(group)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PromptTemplate>()), 0)
    }

    // MARK: - File format round-trip

    func testParse_validFrontmatter() {
        let source = """
        ---
        name: "Review PR"
        sortOrder: 3
        ---

        Review PR #___.
        Ask me for the PR number first.
        """
        let dto = ConfigFileManager.parsePromptTemplateContent(source, fallbackName: "fallback")
        XCTAssertEqual(dto.name, "Review PR")
        XCTAssertEqual(dto.sortOrder, 3)
        XCTAssertEqual(dto.prompt, "Review PR #___.\nAsk me for the PR number first.")
    }

    func testParse_missingFrontmatter_usesFallback() {
        let source = "Just a raw prompt with no frontmatter."
        let dto = ConfigFileManager.parsePromptTemplateContent(source, fallbackName: "raw-prompt")
        XCTAssertEqual(dto.name, "raw-prompt")
        XCTAssertEqual(dto.sortOrder, 0)
        XCTAssertEqual(dto.prompt, source)
    }

    func testSerialize_thenParse_roundTrips() {
        let original = PromptTemplateFileDTO(
            name: "Design a solution",
            sortOrder: 2,
            prompt: "Propose 2-3 approaches with trade-offs before implementing."
        )
        let serialized = ConfigFileManager.serializePromptTemplate(original)
        let parsed = ConfigFileManager.parsePromptTemplateContent(serialized, fallbackName: "x")
        XCTAssertEqual(parsed.name, original.name)
        XCTAssertEqual(parsed.sortOrder, original.sortOrder)
        XCTAssertEqual(parsed.prompt, original.prompt)
    }

    func testSerialize_escapesQuotesInName() {
        let dto = PromptTemplateFileDTO(
            name: "Say \"hello\"",
            sortOrder: 1,
            prompt: "Greet politely."
        )
        let serialized = ConfigFileManager.serializePromptTemplate(dto)
        // The frontmatter line must remain valid YAML-ish — i.e. the inner
        // quote is escaped so the surrounding quotes still bracket the value.
        XCTAssertTrue(serialized.contains("name: \"Say \\\"hello\\\"\""))
    }
}
