import SwiftData
import XCTest
@testable import ClaudPeer

@MainActor
final class CatalogServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self,
            ConversationMessage.self, MessageAttachment.self,
            Skill.self, MCPServer.self, PermissionSet.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Catalog Loading

    func testAllAgentsNotEmpty() {
        let agents = CatalogService.shared.allAgents()
        XCTAssertFalse(agents.isEmpty, "Agent catalog should not be empty")
    }

    func testAllSkillsNotEmpty() {
        let skills = CatalogService.shared.allSkills()
        XCTAssertFalse(skills.isEmpty, "Skill catalog should not be empty")
    }

    func testAllMCPsNotEmpty() {
        let mcps = CatalogService.shared.allMCPs()
        XCTAssertFalse(mcps.isEmpty, "MCP catalog should not be empty")
    }

    func testAgentCatalogHasExpectedCount() {
        let agents = CatalogService.shared.allAgents()
        XCTAssertEqual(agents.count, 30, "Should have 30 agents in catalog")
    }

    func testSkillCatalogHasExpectedCount() {
        let skills = CatalogService.shared.allSkills()
        XCTAssertEqual(skills.count, 101, "Should have 101 skills in catalog")
    }

    func testMCPCatalogHasExpectedCount() {
        let mcps = CatalogService.shared.allMCPs()
        XCTAssertEqual(mcps.count, 100, "Should have 100 MCPs in catalog")
    }

    // MARK: - Find Operations

    func testFindAgent() {
        let agent = CatalogService.shared.findAgent("orchestrator")
        XCTAssertNotNil(agent)
        XCTAssertEqual(agent?.name, "Orchestrator")
    }

    func testFindSkill() {
        let skill = CatalogService.shared.findSkill("code-review")
        XCTAssertNotNil(skill)
        XCTAssertEqual(skill?.name, "Code Review")
    }

    func testFindMCP() {
        let mcp = CatalogService.shared.findMCP("github")
        XCTAssertNotNil(mcp)
        XCTAssertEqual(mcp?.name, "GitHub")
    }

    func testFindNonexistentReturnsNil() {
        XCTAssertNil(CatalogService.shared.findAgent("nonexistent-agent-xyz"))
        XCTAssertNil(CatalogService.shared.findSkill("nonexistent-skill-xyz"))
        XCTAssertNil(CatalogService.shared.findMCP("nonexistent-mcp-xyz"))
    }

    // MARK: - Categories

    func testAgentCategoriesNotEmpty() {
        let categories = CatalogService.shared.agentCategories()
        XCTAssertFalse(categories.isEmpty)
        XCTAssertTrue(categories.contains("Core Team"))
    }

    func testSkillCategoriesNotEmpty() {
        let categories = CatalogService.shared.skillCategories()
        XCTAssertFalse(categories.isEmpty)
        XCTAssertTrue(categories.contains("Development"))
    }

    func testMCPCategoriesNotEmpty() {
        let categories = CatalogService.shared.mcpCategories()
        XCTAssertFalse(categories.isEmpty)
    }

    func testCategoriesAreSorted() {
        let agentCats = CatalogService.shared.agentCategories()
        XCTAssertEqual(agentCats, agentCats.sorted())

        let skillCats = CatalogService.shared.skillCategories()
        XCTAssertEqual(skillCats, skillCats.sorted())

        let mcpCats = CatalogService.shared.mcpCategories()
        XCTAssertEqual(mcpCats, mcpCats.sorted())
    }

    // MARK: - Agent System Prompts

    func testAgentsHaveSystemPrompts() {
        let agents = CatalogService.shared.allAgents()
        let agentsWithPrompts = agents.filter { !$0.systemPrompt.isEmpty }
        XCTAssertEqual(agentsWithPrompts.count, agents.count,
                       "All agents should have system prompts loaded from .md files")
    }

    func testOrchestratorSystemPromptHasContent() {
        let agent = CatalogService.shared.findAgent("orchestrator")
        XCTAssertNotNil(agent)
        XCTAssertFalse(agent!.systemPrompt.isEmpty)
        XCTAssertTrue(agent!.systemPrompt.contains("Identity") || agent!.systemPrompt.contains("identity"),
                      "System prompt should contain an Identity section")
    }

    // MARK: - Skill Content

    func testSkillsHaveContent() {
        let skills = CatalogService.shared.allSkills()
        let skillsWithContent = skills.filter { !$0.content.isEmpty }
        XCTAssertEqual(skillsWithContent.count, skills.count,
                       "All skills should have content loaded from .md files")
    }

    // MARK: - Install / Uninstall

    func testInstallMCP() {
        let server = CatalogService.shared.installMCP("github", into: context)
        XCTAssertNotNil(server)
        XCTAssertEqual(server?.name, "GitHub")
        XCTAssertEqual(server?.catalogId, "github")
        XCTAssertTrue(CatalogService.shared.isMCPInstalled("github", context: context))
    }

    func testInstallMCPIdempotent() {
        let first = CatalogService.shared.installMCP("github", into: context)
        let second = CatalogService.shared.installMCP("github", into: context)
        XCTAssertEqual(first?.id, second?.id, "Installing same MCP twice returns the same instance")
    }

    func testUninstallMCP() {
        CatalogService.shared.installMCP("github", into: context)
        XCTAssertTrue(CatalogService.shared.isMCPInstalled("github", context: context))

        CatalogService.shared.uninstallMCP(catalogId: "github", context: context)
        XCTAssertFalse(CatalogService.shared.isMCPInstalled("github", context: context))
    }

    func testInstallSkill() {
        let skill = CatalogService.shared.installSkill("code-review", into: context)
        XCTAssertNotNil(skill)
        XCTAssertEqual(skill?.name, "Code Review")
        XCTAssertEqual(skill?.catalogId, "code-review")
        XCTAssertTrue(CatalogService.shared.isSkillInstalled("code-review", context: context))
    }

    func testInstallSkillCascadesMCPs() {
        let catalogSkill = CatalogService.shared.findSkill("code-review")
        XCTAssertNotNil(catalogSkill)

        CatalogService.shared.installSkill("code-review", into: context)

        for mcpId in catalogSkill!.requiredMCPs {
            XCTAssertTrue(CatalogService.shared.isMCPInstalled(mcpId, context: context),
                         "Required MCP '\(mcpId)' should be auto-installed with skill")
        }
    }

    func testUninstallSkill() {
        CatalogService.shared.installSkill("code-review", into: context)
        XCTAssertTrue(CatalogService.shared.isSkillInstalled("code-review", context: context))

        CatalogService.shared.uninstallSkill(catalogId: "code-review", context: context)
        XCTAssertFalse(CatalogService.shared.isSkillInstalled("code-review", context: context))
    }

    func testInstallAgent() {
        let agent = CatalogService.shared.installAgent("orchestrator", into: context)
        XCTAssertNotNil(agent)
        XCTAssertEqual(agent?.name, "Orchestrator")
        XCTAssertEqual(agent?.catalogId, "orchestrator")
        XCTAssertTrue(CatalogService.shared.isAgentInstalled("orchestrator", context: context))
    }

    func testInstallAgentSetsSystemPrompt() {
        let agent = CatalogService.shared.installAgent("orchestrator", into: context)
        XCTAssertNotNil(agent)
        XCTAssertFalse(agent!.systemPrompt.isEmpty,
                       "Installed agent should have system prompt from catalog .md file")
    }

    func testInstallAgentCascadesSkillsAndMCPs() {
        let catalogAgent = CatalogService.shared.findAgent("orchestrator")
        XCTAssertNotNil(catalogAgent)

        CatalogService.shared.installAgent("orchestrator", into: context)

        for skillId in catalogAgent!.requiredSkills {
            XCTAssertTrue(CatalogService.shared.isSkillInstalled(skillId, context: context),
                         "Required skill '\(skillId)' should be auto-installed with agent")
        }
    }

    func testInstallAgentIdempotent() {
        let first = CatalogService.shared.installAgent("orchestrator", into: context)
        let second = CatalogService.shared.installAgent("orchestrator", into: context)
        XCTAssertEqual(first?.id, second?.id)
    }

    func testUninstallAgent() {
        CatalogService.shared.installAgent("orchestrator", into: context)
        XCTAssertTrue(CatalogService.shared.isAgentInstalled("orchestrator", context: context))

        CatalogService.shared.uninstallAgent(catalogId: "orchestrator", context: context)
        XCTAssertFalse(CatalogService.shared.isAgentInstalled("orchestrator", context: context))
    }

    func testInstallNonexistentReturnsNil() {
        XCTAssertNil(CatalogService.shared.installAgent("fake-id", into: context))
        XCTAssertNil(CatalogService.shared.installSkill("fake-id", into: context))
        XCTAssertNil(CatalogService.shared.installMCP("fake-id", into: context))
    }

    // MARK: - Dependency Resolution

    func testResolveDependenciesForAgent() {
        let agent = CatalogService.shared.findAgent("orchestrator")!
        let deps = CatalogService.shared.resolveDependencies(forAgent: agent, context: context)

        XCTAssertFalse(deps.skills.isEmpty || agent.requiredSkills.isEmpty,
                       "Orchestrator should have required skills to resolve")
        XCTAssertTrue(deps.missingSkillIds.isEmpty,
                       "All orchestrator skills should exist in catalog")
    }

    func testResolveDependenciesExcludesInstalled() {
        let agent = CatalogService.shared.findAgent("orchestrator")!

        let depsBefore = CatalogService.shared.resolveDependencies(forAgent: agent, context: context)
        let skillCountBefore = depsBefore.skills.count

        if let firstSkillId = agent.requiredSkills.first {
            CatalogService.shared.installSkill(firstSkillId, into: context)
        }

        let depsAfter = CatalogService.shared.resolveDependencies(forAgent: agent, context: context)
        XCTAssertLessThan(depsAfter.skills.count, skillCountBefore,
                         "After installing a skill, dependency count should decrease")
    }

    // MARK: - Catalog Data Integrity

    func testAllAgentsHaveUniqueIds() {
        let agents = CatalogService.shared.allAgents()
        let ids = agents.map(\.catalogId)
        XCTAssertEqual(ids.count, Set(ids).count, "All agent catalogIds should be unique")
    }

    func testAllSkillsHaveUniqueIds() {
        let skills = CatalogService.shared.allSkills()
        let ids = skills.map(\.catalogId)
        XCTAssertEqual(ids.count, Set(ids).count, "All skill catalogIds should be unique")
    }

    func testAllMCPsHaveUniqueIds() {
        let mcps = CatalogService.shared.allMCPs()
        let ids = mcps.map(\.catalogId)
        XCTAssertEqual(ids.count, Set(ids).count, "All MCP catalogIds should be unique")
    }

    func testAllAgentsHaveValidSkillReferences() {
        let agents = CatalogService.shared.allAgents()
        for agent in agents {
            for skillId in agent.requiredSkills {
                XCTAssertNotNil(CatalogService.shared.findSkill(skillId),
                               "Agent '\(agent.name)' references unknown skill '\(skillId)'")
            }
        }
    }

    func testAllSkillsHaveValidMCPReferences() {
        let skills = CatalogService.shared.allSkills()
        for skill in skills {
            for mcpId in skill.requiredMCPs {
                XCTAssertNotNil(CatalogService.shared.findMCP(mcpId),
                               "Skill '\(skill.name)' references unknown MCP '\(mcpId)'")
            }
        }
    }

    func testAllAgentsHaveRequiredFields() {
        for agent in CatalogService.shared.allAgents() {
            XCTAssertFalse(agent.name.isEmpty, "Agent catalogId=\(agent.catalogId) has empty name")
            XCTAssertFalse(agent.description.isEmpty, "Agent '\(agent.name)' has empty description")
            XCTAssertFalse(agent.icon.isEmpty, "Agent '\(agent.name)' has empty icon")
            XCTAssertFalse(agent.color.isEmpty, "Agent '\(agent.name)' has empty color")
            XCTAssertFalse(agent.model.isEmpty, "Agent '\(agent.name)' has empty model")
        }
    }

    func testAllSkillsHaveRequiredFields() {
        for skill in CatalogService.shared.allSkills() {
            XCTAssertFalse(skill.name.isEmpty, "Skill catalogId=\(skill.catalogId) has empty name")
            XCTAssertFalse(skill.description.isEmpty, "Skill '\(skill.name)' has empty description")
            XCTAssertFalse(skill.icon.isEmpty, "Skill '\(skill.name)' has empty icon")
            XCTAssertFalse(skill.category.isEmpty, "Skill '\(skill.name)' has empty category")
        }
    }

    func testAllMCPsHaveRequiredFields() {
        for mcp in CatalogService.shared.allMCPs() {
            XCTAssertFalse(mcp.name.isEmpty, "MCP catalogId=\(mcp.catalogId) has empty name")
            XCTAssertFalse(mcp.description.isEmpty, "MCP '\(mcp.name)' has empty description")
            XCTAssertFalse(mcp.icon.isEmpty, "MCP '\(mcp.name)' has empty icon")
            XCTAssertFalse(mcp.transport.kind.isEmpty, "MCP '\(mcp.name)' has empty transport kind")
        }
    }
}
