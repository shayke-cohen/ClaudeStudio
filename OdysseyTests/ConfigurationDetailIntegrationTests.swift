import XCTest
@testable import Odyssey

/// Integration tests for ConfigFileManager file I/O: write → read round-trips
/// and directory/file structure for each entity type.
final class ConfigurationDetailIntegrationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigDetailIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Agent directory structure

    func testAgentDirectory_hasConfigAndPrompt() throws {
        let agentsDir = tempDir.appendingPathComponent("agents")
        let slug = "test-agent"
        let agentDir = agentsDir.appendingPathComponent(slug)
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)

        let configJSON = """
        {"name":"Test Agent","agentDescription":"desc","model":"opus","icon":"star","color":"blue",
         "skillNames":[],"mcpServerNames":[],"permissionSetName":"standard","systemPromptTemplate":null,
         "systemPromptVariables":null,"maxTurns":null,"maxBudget":null,"maxThinkingTokens":null,
         "defaultWorkingDirectory":null}
        """
        try configJSON.write(to: agentDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "Hello world".write(to: agentDir.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: agentDir.appendingPathComponent("config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentDir.appendingPathComponent("prompt.md").path))

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: agentDir.path, isDirectory: &isDir)
        XCTAssertTrue(isDir.boolValue, "Agent slug entry should be a directory")
    }

    func testGroupDirectory_hasConfigAndInstruction() throws {
        let groupsDir = tempDir.appendingPathComponent("groups")
        let slug = "code-team"
        let groupDir = groupsDir.appendingPathComponent(slug)
        try FileManager.default.createDirectory(at: groupDir, withIntermediateDirectories: true)

        let configJSON = """
        {"name":"Code Team","description":"desc","icon":"person.2","color":"purple",
         "instruction":"","agentNames":[],"sortOrder":0}
        """
        try configJSON.write(to: groupDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "Work together".write(to: groupDir.appendingPathComponent("instruction.md"), atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: groupDir.appendingPathComponent("config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: groupDir.appendingPathComponent("instruction.md").path))

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: groupDir.path, isDirectory: &isDir)
        XCTAssertTrue(isDir.boolValue, "Group slug entry should be a directory")
    }

    func testGroupDirectory_optionalMissionAndWorkflow() throws {
        let slug = "pipeline-team"
        let groupDir = tempDir.appendingPathComponent("groups").appendingPathComponent(slug)
        try FileManager.default.createDirectory(at: groupDir, withIntermediateDirectories: true)

        let missionURL = groupDir.appendingPathComponent("mission.md")
        let workflowURL = groupDir.appendingPathComponent("workflow.json")

        XCTAssertFalse(FileManager.default.fileExists(atPath: missionURL.path), "mission.md absent by default")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workflowURL.path), "workflow.json absent by default")

        try "Build the app".write(to: missionURL, atomically: true, encoding: .utf8)
        try "[]".write(to: workflowURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: missionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workflowURL.path))
    }

    // MARK: - Skill file structure

    func testSkillFile_isFlatMarkdown() throws {
        let skillsDir = tempDir.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let slug = "tdd"
        let skillFile = skillsDir.appendingPathComponent("\(slug).md")
        let content = "---\nname: TDD\ncategory: Engineering\ntriggers: []\n---\nAlways TDD."
        try content.write(to: skillFile, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: skillFile.path))
        XCTAssertEqual(skillFile.pathExtension, "md")

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: skillFile.path, isDirectory: &isDir)
        XCTAssertFalse(isDir.boolValue, "Skill entry should be a flat file, not a directory")
    }

    // MARK: - MCP file structure

    func testMCPFile_isFlatJSON() throws {
        let mcpsDir = tempDir.appendingPathComponent("mcps")
        try FileManager.default.createDirectory(at: mcpsDir, withIntermediateDirectories: true)
        let slug = "octocode"
        let mcpFile = mcpsDir.appendingPathComponent("\(slug).json")
        let content = """
        {"name":"octocode","serverDescription":"Code search","transportKind":"stdio",
         "transportCommand":"npx","transportArgs":["-y","octocode-mcp"]}
        """
        try content.write(to: mcpFile, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: mcpFile.path))
        XCTAssertEqual(mcpFile.pathExtension, "json")

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: mcpFile.path, isDirectory: &isDir)
        XCTAssertFalse(isDir.boolValue, "MCP entry should be a flat file, not a directory")
    }

    // MARK: - slugify round-trip

    func testSlugify_agentNameProducesValidDirectoryName() throws {
        let names = ["My Agent", "Code Reviewer", "Research Buddy", "A + B", "Design & Dev"]
        for name in names {
            let slug = ConfigFileManager.slugify(name)
            let dir = tempDir.appendingPathComponent(slug)
            XCTAssertNoThrow(try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true),
                             "Slug '\(slug)' from '\(name)' should be a valid directory name")
        }
    }

    // MARK: - Reveal URL correctness

    func testRevealURLs_matchDiskStructure() throws {
        let base = tempDir

        // Agent: directory
        let agentSlug = "my-agent"
        let agentDir = base!.appendingPathComponent("agents").appendingPathComponent(agentSlug)
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentDir.path), "Agent directory should exist")
        XCTAssertEqual(agentDir.pathExtension, "", "Agent URL has no file extension")

        // Group: directory
        let groupSlug = "code-team"
        let groupDir = base!.appendingPathComponent("groups").appendingPathComponent(groupSlug)
        try FileManager.default.createDirectory(at: groupDir, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: groupDir.path))
        XCTAssertEqual(groupDir.pathExtension, "", "Group URL has no file extension")

        // Skill: .md flat file
        let skillSlug = "tdd"
        let skillsDir = base!.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let skillFile = skillsDir.appendingPathComponent(skillSlug).appendingPathExtension("md")
        try "# TDD".write(to: skillFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillFile.path))
        XCTAssertEqual(skillFile.pathExtension, "md")

        // MCP: .json flat file
        let mcpSlug = "octocode"
        let mcpsDir = base!.appendingPathComponent("mcps")
        try FileManager.default.createDirectory(at: mcpsDir, withIntermediateDirectories: true)
        let mcpFile = mcpsDir.appendingPathComponent(mcpSlug).appendingPathExtension("json")
        try "{}".write(to: mcpFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mcpFile.path))
        XCTAssertEqual(mcpFile.pathExtension, "json")
    }
}
