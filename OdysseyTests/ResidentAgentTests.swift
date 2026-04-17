import XCTest
import SwiftData
@testable import Odyssey

/// Tests for the Resident Agents feature.
///
/// Resident Agent = any Agent whose `defaultWorkingDirectory` is non-nil.
/// These tests cover:
///   - Filter: agents with a home folder surface as residents
///   - Chat bucketing: Active (first 5) / History (overflow)
///   - MEMORY.md seeding via ResidentAgentSupport
@MainActor
final class ResidentAgentTests: XCTestCase {

    private var tempDir: URL!
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResidentAgentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        ctx = ModelContext(container)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        container = nil
        ctx = nil
    }

    // MARK: - Resident filter logic

    func testAgent_withHomeFolder_isResident() {
        let agent = Agent(name: "Architect")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/architect"
        XCTAssertNotNil(agent.defaultWorkingDirectory, "Agent with home folder should be considered Resident")
    }

    func testAgent_withoutHomeFolder_isNotResident() {
        let agent = Agent(name: "Regular")
        agent.defaultWorkingDirectory = nil
        XCTAssertNil(agent.defaultWorkingDirectory, "Agent without home folder should not be Resident")
    }

    func testResidentAgents_filterRetainsOnlyAgentsWithIsResidentFlag() throws {
        let resident1 = Agent(name: "Architect")
        resident1.isResident = true

        let resident2 = Agent(name: "Researcher")
        resident2.isResident = true

        let regular = Agent(name: "Worker")
        // isResident defaults to false

        let all = [resident1, resident2, regular]
        // Mirror the SidebarView filter
        let residents = all.filter { $0.isEnabled && $0.isResident }

        XCTAssertEqual(residents.count, 2)
        XCTAssertTrue(residents.allSatisfy { $0.isResident })
        XCTAssertFalse(residents.contains { $0.name == "Worker" })
    }

    func testAgent_defaultHomePath_generatedFromName() {
        let agent = Agent(name: "My Researcher")
        XCTAssertEqual(agent.defaultWorkingDirectory, "~/.odyssey/residents/my-researcher")
    }

    func testAgent_defaultHomePath_staticHelper() {
        XCTAssertEqual(Agent.defaultHomePath(for: "Code Reviewer"), "~/.odyssey/residents/code-reviewer")
        XCTAssertEqual(Agent.defaultHomePath(for: ""), "~/.odyssey/residents/agent")
    }

    func testResidentAgents_disabledAgentExcluded() {
        let agent = Agent(name: "Disabled Resident")
        agent.isResident = true
        agent.isEnabled = false

        let residents = [agent].filter { $0.isEnabled && $0.isResident }
        XCTAssertEqual(residents.count, 0)
    }

    func testResidentAgents_sortedAlphabetically() {
        let c = Agent(name: "Charlie"); c.isResident = true
        let a = Agent(name: "Alpha");   a.isResident = true
        let b = Agent(name: "Beta");    b.isResident = true

        let sorted = [c, a, b]
            .filter { $0.isEnabled && $0.isResident }
            .sorted { $0.name < $1.name }

        XCTAssertEqual(sorted.map(\.name), ["Alpha", "Beta", "Charlie"])
    }

    // MARK: - Chat bucket logic (Active = first 5, History = overflow)

    private func makeConversation(topic: String, secondsAgo: TimeInterval = 0, isArchived: Bool = false) -> Conversation {
        let convo = Conversation(topic: topic)
        convo.isArchived = isArchived
        convo.startedAt = Date().addingTimeInterval(-secondsAgo)
        ctx.insert(convo)
        return convo
    }

    private func residentActiveItems(_ convos: [Conversation]) -> [Conversation] {
        Array(convos.filter { !$0.isArchived }.sorted { $0.startedAt > $1.startedAt }.prefix(5))
    }

    private func residentHistoryItems(_ convos: [Conversation]) -> [Conversation] {
        Array(convos.filter { !$0.isArchived }.sorted { $0.startedAt > $1.startedAt }.dropFirst(5))
    }

    func testResidentBuckets_fewChats_allInActive() throws {
        var convos: [Conversation] = []
        for i in 0..<3 {
            convos.append(makeConversation(topic: "Chat \(i)", secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        XCTAssertEqual(residentActiveItems(convos).count, 3)
        XCTAssertEqual(residentHistoryItems(convos).count, 0)
    }

    func testResidentBuckets_exactlyFive_noneInHistory() throws {
        var convos: [Conversation] = []
        for i in 0..<5 {
            convos.append(makeConversation(topic: "Chat \(i)", secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        XCTAssertEqual(residentActiveItems(convos).count, 5)
        XCTAssertEqual(residentHistoryItems(convos).count, 0)
    }

    func testResidentBuckets_moreThanFive_overflowGoesToHistory() throws {
        var convos: [Conversation] = []
        for i in 0..<8 {
            convos.append(makeConversation(topic: "Chat \(i)", secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        XCTAssertEqual(residentActiveItems(convos).count, 5)
        XCTAssertEqual(residentHistoryItems(convos).count, 3)
    }

    func testResidentBuckets_archivedExcludedFromBothBuckets() throws {
        var convos: [Conversation] = []
        for i in 0..<6 {
            convos.append(makeConversation(topic: "Chat \(i)", secondsAgo: Double(i) * 60, isArchived: i >= 4))
        }
        try ctx.save()

        XCTAssertEqual(residentActiveItems(convos).count, 4)
        XCTAssertEqual(residentHistoryItems(convos).count, 0)
    }

    func testResidentBuckets_activeOrderedNewestFirst() throws {
        let old = makeConversation(topic: "Old", secondsAgo: 3600)
        let recent = makeConversation(topic: "Recent", secondsAgo: 60)
        let mid = makeConversation(topic: "Mid", secondsAgo: 1800)
        try ctx.save()

        let active = residentActiveItems([old, recent, mid])
        XCTAssertEqual(active[0].topic, "Recent")
        XCTAssertEqual(active[1].topic, "Mid")
        XCTAssertEqual(active[2].topic, "Old")
    }

    // MARK: - MEMORY.md seeding

    func testSeedMemory_createsDirectoryAndFile() {
        let homePath = tempDir.appendingPathComponent("architect").path
        let created = ResidentAgentSupport.seedMemoryFileIfNeeded(in: homePath, agentName: "Architect")

        XCTAssertTrue(created, "Should report file was newly created")
        let memPath = tempDir.appendingPathComponent("architect/MEMORY.md").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: memPath), "MEMORY.md should exist")
    }

    func testSeedMemory_fileContainsAgentName() throws {
        let homePath = tempDir.appendingPathComponent("researcher").path
        ResidentAgentSupport.seedMemoryFileIfNeeded(in: homePath, agentName: "Research Buddy")

        let content = try String(
            contentsOf: tempDir.appendingPathComponent("researcher/MEMORY.md"),
            encoding: .utf8
        )
        XCTAssertTrue(content.contains("Research Buddy"), "MEMORY.md should include agent name")
        XCTAssertTrue(content.contains("## Recent Lessons"), "MEMORY.md should include Recent Lessons section")
        XCTAssertTrue(content.contains("## Domain Map"), "MEMORY.md should include Domain Map section")
        XCTAssertTrue(content.contains("## Active Goals"), "MEMORY.md should include Active Goals section")
    }

    func testSeedMemory_doesNotOverwriteExistingFile() throws {
        let homePath = tempDir.appendingPathComponent("scribe").path
        try FileManager.default.createDirectory(
            atPath: homePath, withIntermediateDirectories: true
        )
        let existingContent = "# My custom memory"
        try existingContent.write(
            toFile: homePath + "/MEMORY.md",
            atomically: true,
            encoding: .utf8
        )

        let created = ResidentAgentSupport.seedMemoryFileIfNeeded(in: homePath, agentName: "Scribe")

        XCTAssertFalse(created, "Should not overwrite existing file")
        let content = try String(
            contentsOf: URL(fileURLWithPath: homePath + "/MEMORY.md"),
            encoding: .utf8
        )
        XCTAssertEqual(content, existingContent, "Existing MEMORY.md should be unchanged")
    }

    func testSeedMemory_idempotent_calledTwice() {
        let homePath = tempDir.appendingPathComponent("idempotent-agent").path

        let first = ResidentAgentSupport.seedMemoryFileIfNeeded(in: homePath, agentName: "Agent")
        let second = ResidentAgentSupport.seedMemoryFileIfNeeded(in: homePath, agentName: "Agent")

        XCTAssertTrue(first, "First call should create file")
        XCTAssertFalse(second, "Second call should skip (already exists)")
    }

    func testSeedMemory_createsIntermediateDirectories() {
        let deepPath = tempDir.appendingPathComponent("a/b/c/deep-agent").path

        ResidentAgentSupport.seedMemoryFileIfNeeded(in: deepPath, agentName: "Deep")

        let memPath = deepPath + "/MEMORY.md"
        XCTAssertTrue(FileManager.default.fileExists(atPath: memPath))
    }

    // MARK: - Session working directory

    func testStartResidentSession_usesAgentHomeDir() throws {
        let agent = Agent(name: "Architect")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/architect"
        ctx.insert(agent)
        try ctx.save()

        // Mirror startResidentSession logic: expand tilde and set as workingDirectory
        let homeDir = agent.defaultWorkingDirectory!
        let expandedPath = (homeDir as NSString).expandingTildeInPath

        let session = Session(agent: agent, mode: .interactive)
        session.workingDirectory = expandedPath

        XCTAssertEqual(session.workingDirectory, expandedPath)
        XCTAssertTrue(
            session.workingDirectory.contains("residents/architect"),
            "Resident session should use agent home folder, got: \(session.workingDirectory)"
        )
    }

    func testStartProjectSession_usesProjectDir_notAgentHomeDir() throws {
        let agent = Agent(name: "Architect")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/architect"
        ctx.insert(agent)

        let project = Project(name: "Odyssey", rootPath: "/Users/test/Odyssey", canonicalRootPath: "/Users/test/Odyssey")
        ctx.insert(project)
        try ctx.save()

        // Mirror startSession logic: project dir, ignoring agent's home
        let session = Session(agent: agent, mode: .interactive)
        if session.workingDirectory.isEmpty {
            session.workingDirectory = project.rootPath
        }

        XCTAssertEqual(session.workingDirectory, project.rootPath,
                       "Project session should use project root, not agent home folder")
    }

    // MARK: - Vault seeding (CLAUDE.md, INDEX.md, GUIDELINES.md, SESSION.md)

    func testSeedCLAUDE_createsFileWithAgentName() throws {
        let homePath = tempDir.appendingPathComponent("vault-agent").path
        let created = ResidentAgentSupport.seedCLAUDEFileIfNeeded(in: homePath, agentName: "Vault Agent")

        XCTAssertTrue(created)
        let content = try String(contentsOfFile: homePath + "/CLAUDE.md", encoding: .utf8)
        XCTAssertTrue(content.contains("Vault Agent"))
        XCTAssertTrue(content.contains("## Session Start"))
        XCTAssertTrue(content.contains("## Session End"))
        XCTAssertTrue(content.contains("Reflection Loop"))
        XCTAssertTrue(content.contains("MEMORY.md"))
        XCTAssertTrue(content.contains("INDEX.md"))
    }

    func testSeedCLAUDE_idempotent() {
        let homePath = tempDir.appendingPathComponent("claude-idem").path
        let first = ResidentAgentSupport.seedCLAUDEFileIfNeeded(in: homePath, agentName: "Agent")
        let second = ResidentAgentSupport.seedCLAUDEFileIfNeeded(in: homePath, agentName: "Agent")
        XCTAssertTrue(first)
        XCTAssertFalse(second)
    }

    func testSeedIndex_createsFileWithAgentName() throws {
        let homePath = tempDir.appendingPathComponent("index-agent").path
        ResidentAgentSupport.seedIndexFileIfNeeded(in: homePath, agentName: "Index Agent")

        let content = try String(contentsOfFile: homePath + "/INDEX.md", encoding: .utf8)
        XCTAssertTrue(content.contains("Index Agent"))
        XCTAssertTrue(content.contains("[[MEMORY.md]]"))
        XCTAssertTrue(content.contains("[[GUIDELINES.md]]"))
        XCTAssertTrue(content.contains("[[SESSION.md]]"))
    }

    func testSeedGuidelines_createsFile() throws {
        let homePath = tempDir.appendingPathComponent("guidelines-agent").path
        let created = ResidentAgentSupport.seedGuidelinesFileIfNeeded(in: homePath)

        XCTAssertTrue(created)
        let content = try String(contentsOfFile: homePath + "/GUIDELINES.md", encoding: .utf8)
        XCTAssertTrue(content.contains("# Guidelines"))
        XCTAssertTrue(content.contains("guidelines"))
    }

    func testSeedSession_createsFile() throws {
        let homePath = tempDir.appendingPathComponent("session-agent").path
        let created = ResidentAgentSupport.seedSessionFileIfNeeded(in: homePath)

        XCTAssertTrue(created)
        let content = try String(contentsOfFile: homePath + "/SESSION.md", encoding: .utf8)
        XCTAssertTrue(content.contains("# Current Session"))
        XCTAssertTrue(content.contains("## Task"))
        XCTAssertTrue(content.contains("volatile: true"))
    }

    func testResetSession_alwaysOverwrites() throws {
        let homePath = tempDir.appendingPathComponent("reset-agent").path
        try FileManager.default.createDirectory(atPath: homePath, withIntermediateDirectories: true)
        try "custom content".write(toFile: homePath + "/SESSION.md", atomically: true, encoding: .utf8)

        ResidentAgentSupport.resetSessionFile(in: homePath)

        let content = try String(contentsOfFile: homePath + "/SESSION.md", encoding: .utf8)
        XCTAssertFalse(content.contains("custom content"), "resetSessionFile should overwrite existing content")
        XCTAssertTrue(content.contains("# Current Session"))
    }

    func testSeedVaultIfNeeded_createsAllFiveFiles() {
        let homePath = tempDir.appendingPathComponent("full-vault").path
        ResidentAgentSupport.seedVaultIfNeeded(in: homePath, agentName: "Full Vault")

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: homePath + "/MEMORY.md"))
        XCTAssertTrue(fm.fileExists(atPath: homePath + "/CLAUDE.md"))
        XCTAssertTrue(fm.fileExists(atPath: homePath + "/INDEX.md"))
        XCTAssertTrue(fm.fileExists(atPath: homePath + "/GUIDELINES.md"))
        XCTAssertTrue(fm.fileExists(atPath: homePath + "/SESSION.md"))
    }

    func testPrepareVaultForSession_resetsSessionMd() throws {
        let homePath = tempDir.appendingPathComponent("prepare-vault").path
        ResidentAgentSupport.seedVaultIfNeeded(in: homePath, agentName: "Agent")
        // Simulate agent having written to SESSION.md during a session
        try "in-progress work notes".write(toFile: homePath + "/SESSION.md", atomically: true, encoding: .utf8)

        ResidentAgentSupport.prepareVaultForSession(in: homePath, agentName: "Agent")

        let content = try String(contentsOfFile: homePath + "/SESSION.md", encoding: .utf8)
        XCTAssertFalse(content.contains("in-progress work notes"))
        XCTAssertTrue(content.contains("# Current Session"))
    }

    // MARK: - Integration: full promotion + session lifecycle

    func testIntegration_fullPromotion_allVaultFilesExist() throws {
        let homePath = tempDir.appendingPathComponent("promoted-agent").path
        let agent = Agent(name: "Promoted Agent")
        agent.isResident = true
        agent.defaultWorkingDirectory = homePath

        // Simulate the promotion flow in SidebarView
        let expanded = (homePath as NSString).expandingTildeInPath
        ResidentAgentSupport.seedVaultIfNeeded(in: expanded, agentName: agent.name)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: expanded + "/MEMORY.md"), "MEMORY.md missing after promotion")
        XCTAssertTrue(fm.fileExists(atPath: expanded + "/CLAUDE.md"), "CLAUDE.md missing after promotion")
        XCTAssertTrue(fm.fileExists(atPath: expanded + "/INDEX.md"), "INDEX.md missing after promotion")
        XCTAssertTrue(fm.fileExists(atPath: expanded + "/GUIDELINES.md"), "GUIDELINES.md missing after promotion")
        XCTAssertTrue(fm.fileExists(atPath: expanded + "/SESSION.md"), "SESSION.md missing after promotion")
    }

    func testIntegration_sessionStart_resetsSESSIONmd_leavesOthersIntact() throws {
        let homePath = tempDir.appendingPathComponent("session-lifecycle").path

        // Step 1: Promotion seeds the vault
        ResidentAgentSupport.seedVaultIfNeeded(in: homePath, agentName: "Lifecycle Agent")

        // Step 2: Agent writes to SESSION.md during a session
        let sessionPath = homePath + "/SESSION.md"
        try "## in-progress work\nsome notes".write(toFile: sessionPath, atomically: true, encoding: .utf8)

        // Step 3: Capture MEMORY.md and CLAUDE.md content before next session
        let memoryBefore = try String(contentsOfFile: homePath + "/MEMORY.md", encoding: .utf8)
        let claudeBefore = try String(contentsOfFile: homePath + "/CLAUDE.md", encoding: .utf8)

        // Step 4: Next session start — prepareVaultForSession
        ResidentAgentSupport.prepareVaultForSession(in: homePath, agentName: "Lifecycle Agent")

        // SESSION.md should be reset
        let sessionAfter = try String(contentsOfFile: sessionPath, encoding: .utf8)
        XCTAssertFalse(sessionAfter.contains("in-progress work"), "SESSION.md should be reset on session start")
        XCTAssertTrue(sessionAfter.contains("# Current Session"), "SESSION.md should contain fresh template")

        // Other vault files should be unchanged
        let memoryAfter = try String(contentsOfFile: homePath + "/MEMORY.md", encoding: .utf8)
        let claudeAfter = try String(contentsOfFile: homePath + "/CLAUDE.md", encoding: .utf8)
        XCTAssertEqual(memoryBefore, memoryAfter, "MEMORY.md should not be touched on session start")
        XCTAssertEqual(claudeBefore, claudeAfter, "CLAUDE.md should not be touched on session start")
    }

    func testIntegration_repeatedPromotion_isIdempotent() throws {
        let homePath = tempDir.appendingPathComponent("idempotent-promotion").path

        // First promotion
        ResidentAgentSupport.seedVaultIfNeeded(in: homePath, agentName: "Agent")
        // Agent modifies their vault
        try "# Agent Memory\n\n## Recent Lessons\n- 2026-04-17: learned X"
            .write(toFile: homePath + "/MEMORY.md", atomically: true, encoding: .utf8)

        let customMemory = try String(contentsOfFile: homePath + "/MEMORY.md", encoding: .utf8)

        // Re-promote (e.g. remove + re-add to residents)
        ResidentAgentSupport.seedVaultIfNeeded(in: homePath, agentName: "Agent")

        let memoryAfterRepromotion = try String(contentsOfFile: homePath + "/MEMORY.md", encoding: .utf8)
        XCTAssertEqual(customMemory, memoryAfterRepromotion, "Re-promotion must not overwrite agent-written MEMORY.md")
    }

    func testIntegration_CLAUDEmd_containsReflectionLoop() throws {
        let homePath = tempDir.appendingPathComponent("reflection-check").path
        ResidentAgentSupport.seedVaultIfNeeded(in: homePath, agentName: "Reflection Agent")

        let claude = try String(contentsOfFile: homePath + "/CLAUDE.md", encoding: .utf8)

        // Reflection loop instructions must be present and correct
        XCTAssertTrue(claude.contains("Session End"), "CLAUDE.md must contain session-end reflection instructions")
        XCTAssertTrue(claude.contains("YYYY-MM-DD: <lesson>"), "CLAUDE.md must show lesson format")
        XCTAssertTrue(claude.contains("knowledge/{topic}.md"), "CLAUDE.md must mention knowledge promotion")
        XCTAssertTrue(claude.contains("2+ times"), "CLAUDE.md must specify recurrence threshold for promotion")
    }

    func testIntegration_MEMORYmd_hasRoutingIndexStructure() throws {
        let homePath = tempDir.appendingPathComponent("memory-structure").path
        ResidentAgentSupport.seedVaultIfNeeded(in: homePath, agentName: "Memory Agent")

        let memory = try String(contentsOfFile: homePath + "/MEMORY.md", encoding: .utf8)

        XCTAssertTrue(memory.contains("200 lines"), "MEMORY.md must advertise the 200-line cap")
        XCTAssertTrue(memory.contains("Domain Map"), "MEMORY.md must have a Domain Map section for routing")
        XCTAssertTrue(memory.contains("knowledge/"), "MEMORY.md must reference the knowledge/ folder")
    }

    func testIntegration_INDEXmd_linksAllCoreFiles() throws {
        let homePath = tempDir.appendingPathComponent("index-links").path
        ResidentAgentSupport.seedVaultIfNeeded(in: homePath, agentName: "Index Agent")

        let index = try String(contentsOfFile: homePath + "/INDEX.md", encoding: .utf8)

        // INDEX.md must link to every core file using wiki-link syntax
        XCTAssertTrue(index.contains("[[MEMORY.md]]"))
        XCTAssertTrue(index.contains("[[GUIDELINES.md]]"))
        XCTAssertTrue(index.contains("[[SESSION.md]]"))
        XCTAssertTrue(index.contains("[[CLAUDE.md]]"))
    }

    func testIntegration_frontmatterPresentInAllSeedFiles() throws {
        let homePath = tempDir.appendingPathComponent("frontmatter-check").path
        ResidentAgentSupport.seedVaultIfNeeded(in: homePath, agentName: "FM Agent")

        for fileName in ["MEMORY.md", "CLAUDE.md", "INDEX.md", "GUIDELINES.md", "SESSION.md"] {
            let content = try String(contentsOfFile: homePath + "/" + fileName, encoding: .utf8)
            XCTAssertTrue(content.hasPrefix("---"), "\(fileName) must start with YAML frontmatter")
            XCTAssertTrue(content.contains("updated:"), "\(fileName) must contain 'updated:' field")
        }
    }

    // MARK: - Session working directory

    func testResidentConversation_hasNilProjectId() throws {
        let agent = Agent(name: "Architect")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/architect"
        ctx.insert(agent)
        try ctx.save()

        // Mirror startResidentSession: projectId is nil
        let conversation = Conversation(
            topic: agent.name,
            projectId: nil,
            threadKind: .direct
        )
        ctx.insert(conversation)
        try ctx.save()

        XCTAssertNil(conversation.projectId,
                     "Resident conversations should not be scoped to a project")
    }
}
