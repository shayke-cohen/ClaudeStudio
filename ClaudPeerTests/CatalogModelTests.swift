import XCTest
@testable import ClaudPeer

final class CatalogModelTests: XCTestCase {

    // MARK: - CatalogMCP Decoding

    func testDecodeCatalogMCP() throws {
        let json = """
        {
            "catalogId": "github",
            "name": "GitHub",
            "description": "GitHub API access",
            "category": "Developer Tools",
            "icon": "cat.fill",
            "transport": {
                "kind": "stdio",
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-github"],
                "envKeys": ["GITHUB_TOKEN"]
            },
            "popularity": 50000,
            "tags": ["git", "vcs"],
            "homepage": "https://github.com/modelcontextprotocol/servers"
        }
        """.data(using: .utf8)!

        let mcp = try JSONDecoder().decode(CatalogMCP.self, from: json)

        XCTAssertEqual(mcp.catalogId, "github")
        XCTAssertEqual(mcp.name, "GitHub")
        XCTAssertEqual(mcp.id, "github")
        XCTAssertEqual(mcp.category, "Developer Tools")
        XCTAssertEqual(mcp.transport.kind, "stdio")
        XCTAssertEqual(mcp.transport.command, "npx")
        XCTAssertEqual(mcp.transport.args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(mcp.transport.envKeys, ["GITHUB_TOKEN"])
        XCTAssertEqual(mcp.popularity, 50000)
        XCTAssertEqual(mcp.tags, ["git", "vcs"])
        XCTAssertEqual(mcp.homepage, "https://github.com/modelcontextprotocol/servers")
    }

    func testDecodeCatalogMCPWithHTTPTransport() throws {
        let json = """
        {
            "catalogId": "custom-api",
            "name": "Custom API",
            "description": "HTTP-based MCP",
            "category": "API",
            "icon": "globe",
            "transport": {
                "kind": "http",
                "url": "https://mcp.example.com/sse",
                "headerKeys": ["API_KEY"]
            },
            "popularity": 100,
            "tags": ["api"],
            "homepage": "https://example.com"
        }
        """.data(using: .utf8)!

        let mcp = try JSONDecoder().decode(CatalogMCP.self, from: json)

        XCTAssertEqual(mcp.transport.kind, "http")
        XCTAssertEqual(mcp.transport.url, "https://mcp.example.com/sse")
        XCTAssertEqual(mcp.transport.headerKeys, ["API_KEY"])
        XCTAssertNil(mcp.transport.command)
    }

    // MARK: - CatalogSkill Decoding

    func testDecodeCatalogSkill() throws {
        let json = """
        {
            "catalogId": "code-review",
            "name": "Code Review",
            "description": "Systematic code review",
            "category": "Development",
            "icon": "eye.fill",
            "requiredMCPs": ["github"],
            "triggers": ["review", "PR"],
            "tags": ["quality", "review"]
        }
        """.data(using: .utf8)!

        let skill = try JSONDecoder().decode(CatalogSkill.self, from: json)

        XCTAssertEqual(skill.catalogId, "code-review")
        XCTAssertEqual(skill.name, "Code Review")
        XCTAssertEqual(skill.id, "code-review")
        XCTAssertEqual(skill.requiredMCPs, ["github"])
        XCTAssertEqual(skill.triggers, ["review", "PR"])
        XCTAssertEqual(skill.content, "", "Content defaults to empty when not in JSON")
    }

    func testCatalogSkillContentNotInJSON() throws {
        let json = """
        {
            "catalogId": "test-skill",
            "name": "Test",
            "description": "A test skill",
            "category": "Testing",
            "icon": "checkmark",
            "requiredMCPs": [],
            "triggers": [],
            "tags": []
        }
        """.data(using: .utf8)!

        var skill = try JSONDecoder().decode(CatalogSkill.self, from: json)
        XCTAssertEqual(skill.content, "")

        skill.content = "# Test Content\nRich markdown here."
        XCTAssertEqual(skill.content, "# Test Content\nRich markdown here.")
    }

    // MARK: - CatalogAgent Decoding

    func testDecodeCatalogAgent() throws {
        let json = """
        {
            "catalogId": "orchestrator",
            "name": "Orchestrator",
            "description": "Team lead for complex work",
            "category": "Core Team",
            "icon": "brain.head.profile",
            "color": "purple",
            "model": "opus",
            "requiredSkills": ["peer-collaboration", "delegation-patterns"],
            "extraMCPs": [],
            "systemPromptTemplate": "coordinator",
            "systemPromptVariables": {"role": "orchestrator"},
            "tags": ["leadership", "planning"]
        }
        """.data(using: .utf8)!

        let agent = try JSONDecoder().decode(CatalogAgent.self, from: json)

        XCTAssertEqual(agent.catalogId, "orchestrator")
        XCTAssertEqual(agent.name, "Orchestrator")
        XCTAssertEqual(agent.id, "orchestrator")
        XCTAssertEqual(agent.model, "opus")
        XCTAssertEqual(agent.color, "purple")
        XCTAssertEqual(agent.requiredSkills, ["peer-collaboration", "delegation-patterns"])
        XCTAssertEqual(agent.extraMCPs, [])
        XCTAssertEqual(agent.tags, ["leadership", "planning"])
        XCTAssertEqual(agent.systemPrompt, "", "System prompt defaults to empty when not in JSON")
    }

    func testCatalogAgentSystemPromptNotInJSON() throws {
        let json = """
        {
            "catalogId": "coder",
            "name": "Coder",
            "description": "Expert coder",
            "category": "Core Team",
            "icon": "chevron.left.forwardslash.chevron.right",
            "color": "blue",
            "model": "sonnet",
            "requiredSkills": [],
            "extraMCPs": ["github"],
            "systemPromptTemplate": "specialist",
            "systemPromptVariables": {},
            "tags": ["coding"]
        }
        """.data(using: .utf8)!

        var agent = try JSONDecoder().decode(CatalogAgent.self, from: json)
        XCTAssertEqual(agent.systemPrompt, "")

        agent.systemPrompt = "# Identity\nYou are the Coder."
        XCTAssertEqual(agent.systemPrompt, "# Identity\nYou are the Coder.")
    }

    // MARK: - CatalogItem Enum

    func testCatalogItemAgent() throws {
        let json = """
        {
            "catalogId": "test-agent",
            "name": "Test Agent",
            "description": "A test agent",
            "category": "Test",
            "icon": "star",
            "color": "blue",
            "model": "sonnet",
            "requiredSkills": [],
            "extraMCPs": [],
            "systemPromptTemplate": "",
            "systemPromptVariables": {},
            "tags": ["test"]
        }
        """.data(using: .utf8)!

        let agent = try JSONDecoder().decode(CatalogAgent.self, from: json)
        let item = CatalogItem.agent(agent)

        if case .agent(let a) = item {
            XCTAssertEqual(a.name, "Test Agent")
        } else {
            XCTFail("Expected .agent case")
        }
    }

    func testCatalogItemSkill() throws {
        let json = """
        {
            "catalogId": "test-skill",
            "name": "Test Skill",
            "description": "A test skill",
            "category": "Test",
            "icon": "star",
            "requiredMCPs": [],
            "triggers": ["test"],
            "tags": []
        }
        """.data(using: .utf8)!

        let skill = try JSONDecoder().decode(CatalogSkill.self, from: json)
        let item = CatalogItem.skill(skill)

        if case .skill(let s) = item {
            XCTAssertEqual(s.name, "Test Skill")
            XCTAssertEqual(s.triggers, ["test"])
        } else {
            XCTFail("Expected .skill case")
        }
    }

    func testCatalogItemMCP() throws {
        let json = """
        {
            "catalogId": "test-mcp",
            "name": "Test MCP",
            "description": "A test MCP",
            "category": "Test",
            "icon": "server.rack",
            "transport": { "kind": "stdio", "command": "test" },
            "popularity": 500,
            "tags": ["test"],
            "homepage": "https://test.com"
        }
        """.data(using: .utf8)!

        let mcp = try JSONDecoder().decode(CatalogMCP.self, from: json)
        let item = CatalogItem.mcp(mcp)

        if case .mcp(let m) = item {
            XCTAssertEqual(m.name, "Test MCP")
            XCTAssertEqual(m.popularity, 500)
        } else {
            XCTFail("Expected .mcp case")
        }
    }
}
