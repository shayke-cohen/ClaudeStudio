import XCTest
@testable import Odyssey

final class ChatSendRoutingTests: XCTestCase {

    func testParseSlashHelp() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/help"), .help)
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/?"), .help)
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("  /help  "), .help)
    }

    func testParseSlashTopic() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/topic My Title"), .topic("My Title"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/rename  Two  Words"), .topic("Two  Words"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/topic"), .topic(""))
    }

    func testParseSlashAgents() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/agents"), .agents)
    }

    func testDoubleSlashNotCommand() {
        XCTAssertNil(ChatSendRouting.parseSlashCommand("//not a command"))
    }

    func testMentionedAgentNames() {
        let names = ChatSendRouting.mentionedAgentNames(in: "Hi @Coder and @Reviewer please")
        XCTAssertEqual(names, ["Coder", "Reviewer"])
    }

    func testMentionedAgentNamesSupportsAgentNamesWithSpaces() {
        let productManager = Agent(name: "Product manager")
        let reviewer = Agent(name: "Reviewer")

        let names = ChatSendRouting.mentionedAgentNames(
            in: "Loop in @Product manager and @Reviewer.",
            agents: [productManager, reviewer]
        )

        XCTAssertEqual(names, ["Product manager", "Reviewer"])
    }

    func testMentionedAgentNamesPrefersLongestMatchingAgentName() {
        let product = Agent(name: "Product")
        let productManager = Agent(name: "Product manager")

        let names = ChatSendRouting.mentionedAgentNames(
            in: "@Product manager please take point",
            agents: [product, productManager]
        )

        XCTAssertEqual(names, ["Product manager"])
    }

    func testResolveMentionedAgents() {
        let a = Agent(name: "Coder")
        let b = Agent(name: "Reviewer")
        let (resolved, unknown) = ChatSendRouting.resolveMentionedAgents(
            names: ["coder", "Nobody"],
            agents: [a, b]
        )
        XCTAssertEqual(resolved.map(\.id), [a.id])
        XCTAssertEqual(unknown, ["Nobody"])
    }

    func testBareSlashIsNotACommand() {
        XCTAssertNil(ChatSendRouting.parseSlashCommand("/"))
        XCTAssertNil(ChatSendRouting.parseSlashCommand("   /   "))
    }

    func testSlashUsesFirstLineOnly() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/help\nignored"), .help)
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/topic Line1\nLine2"), .topic("Line1"))
    }

    func testUnknownSlashCommand() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/frobnicate"), .unknown("frobnicate"))
    }

    func testResolveMentionedAgentsDeduplicates() {
        let a = Agent(name: "Coder")
        let (resolved, unknown) = ChatSendRouting.resolveMentionedAgents(
            names: ["Coder", "coder", "CODER"],
            agents: [a]
        )
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.id, a.id)
        XCTAssertTrue(unknown.isEmpty)
    }

    func testResolveMentionedAgentsSkipsEmptyTokens() {
        let a = Agent(name: "A")
        let (resolved, unknown) = ChatSendRouting.resolveMentionedAgents(names: ["", "  ", "A"], agents: [a])
        XCTAssertEqual(resolved.map(\.id), [a.id])
        XCTAssertTrue(unknown.isEmpty)
    }

    func testResolveMentionedAgentsIgnoresMentionAllToken() {
        let a = Agent(name: "Reviewer")
        let (resolved, unknown) = ChatSendRouting.resolveMentionedAgents(
            names: ["all", "Reviewer"],
            agents: [a]
        )
        XCTAssertEqual(resolved.map(\.id), [a.id])
        XCTAssertTrue(unknown.isEmpty)
    }

    func testMentionedAgentNamesPreservesOrder() {
        let names = ChatSendRouting.mentionedAgentNames(in: "@Z @A @M")
        XCTAssertEqual(names, ["Z", "A", "M"])
    }

    // MARK: - @all Detection

    func testContainsMentionAll() {
        XCTAssertTrue(ChatSendRouting.containsMentionAll(in: "Hey @all check this"))
    }

    func testContainsMentionAllCaseInsensitive() {
        XCTAssertTrue(ChatSendRouting.containsMentionAll(in: "@ALL please review"))
    }

    func testContainsMentionAllNegative() {
        XCTAssertFalse(ChatSendRouting.containsMentionAll(in: "@Alice hello"))
    }

    func testContainsMentionAllMixedWithNames() {
        XCTAssertTrue(ChatSendRouting.containsMentionAll(in: "@all @Bob status update"))
        let names = ChatSendRouting.mentionedAgentNames(in: "@all @Bob")
        XCTAssertEqual(names, ["all", "Bob"])
    }

    // MARK: - Session commands

    func testParseSlashClear() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/clear"), .clear)
    }

    func testParseSlashCompact() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/compact"), .compact)
    }

    func testParseSlashResume() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/resume"), .resume)
    }

    func testParseSlashExportNoArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/export"), .export(format: nil))
    }

    func testParseSlashExportWithFormat() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/export md"), .export(format: "md"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/export html"), .export(format: "html"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/export json"), .export(format: "json"))
    }

    // MARK: - Model commands

    func testParseSlashModelNoArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/model"), .model(nil))
    }

    func testParseSlashModelWithArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/model claude-opus-4-7"), .model("claude-opus-4-7"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/model claude-haiku-4-5"), .model("claude-haiku-4-5"))
    }

    func testParseSlashEffortNoArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/effort"), .effort(nil))
    }

    func testParseSlashEffortWithLevel() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/effort low"), .effort("low"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/effort medium"), .effort("medium"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/effort high"), .effort("high"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/effort max"), .effort("max"))
    }

    func testParseSlashFast() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/fast"), .fast)
    }

    // MARK: - Memory & Skills commands

    func testParseSlashMemory() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/memory"), .memory)
    }

    func testParseSlashSkills() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/skills"), .skills)
    }

    // MARK: - Agents commands

    func testParseSlashModeNoArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/mode"), .mode(nil))
    }

    func testParseSlashModeWithArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/mode interactive"), .mode("interactive"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/mode autonomous"), .mode("autonomous"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/mode worker"), .mode("worker"))
    }

    func testParseSlashPlan() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/plan"), .plan)
    }

    // MARK: - Tools commands

    func testParseSlashMCP() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/mcp"), .mcp)
    }

    func testParseSlashPermissions() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/permissions"), .permissions)
    }

    // MARK: - Git commands

    func testParseSlashReview() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/review"), .review)
    }

    func testParseSlashDiff() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/diff"), .diff)
    }

    func testParseSlashBranchNoArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/branch"), .branch(action: nil))
    }

    func testParseSlashBranchWithAction() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/branch create"), .branch(action: "create"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/branch switch"), .branch(action: "switch"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/branch list"), .branch(action: "list"))
    }

    func testParseSlashInit() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/init"), .initialize)
    }

    // MARK: - Workflow commands

    func testParseSlashLoopNoArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/loop"), .loop(interval: nil))
    }

    func testParseSlashLoopWithInterval() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/loop 30"), .loop(interval: 30))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/loop 120"), .loop(interval: 120))
    }

    func testParseSlashLoopNonIntegerArgTreatedAsNil() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/loop notanumber"), .loop(interval: nil))
    }

    func testParseSlashSchedule() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/schedule"), .schedule)
    }

    // MARK: - Info commands

    func testParseSlashContext() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/context"), .context)
    }

    func testParseSlashCost() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/cost"), .cost)
    }

    // MARK: - Edge cases for new commands

    func testLeadingWhitespaceStrippedForNewCommands() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("  /clear  "), .clear)
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("  /fast  "), .fast)
    }

    func testNewCommandOnSecondLineIgnored() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/model\nclaude-opus-4-7"), .model(nil))
    }

    func testDoubleSlashDoesNotTriggerNewCommands() {
        XCTAssertNil(ChatSendRouting.parseSlashCommand("//clear"))
        XCTAssertNil(ChatSendRouting.parseSlashCommand("//model opus"))
    }
}
