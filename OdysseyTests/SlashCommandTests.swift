import XCTest
@testable import Odyssey

// MARK: - SlashCommandRegistry tests

final class SlashCommandRegistryTests: XCTestCase {

    // ── Catalog integrity ────────────────────────────────────────────

    func testAllCommandsHaveUniqueIds() {
        let ids = SlashCommandRegistry.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate command IDs found")
    }

    func testAllCommandsHaveNonEmptyDescriptions() {
        for cmd in SlashCommandRegistry.all {
            XCTAssertFalse(cmd.description.isEmpty, "/\(cmd.name) has empty description")
        }
    }

    func testAllCommandsHaveNonEmptyNames() {
        for cmd in SlashCommandRegistry.all {
            XCTAssertFalse(cmd.name.isEmpty, "Command with id=\(cmd.id) has empty name")
        }
    }

    func testIdMatchesName() {
        for cmd in SlashCommandRegistry.all {
            XCTAssertEqual(cmd.id, cmd.name, "/\(cmd.name): id should equal name")
        }
    }

    func testFullCommandHasLeadingSlash() {
        for cmd in SlashCommandRegistry.all {
            XCTAssertEqual(cmd.fullCommand, "/\(cmd.name)")
        }
    }

    func testAllGroupsRepresented() {
        let presentGroups = Set(SlashCommandRegistry.all.map(\.group))
        for group in SlashCommandGroup.allCases {
            XCTAssertTrue(presentGroups.contains(group), "Group \(group) has no commands")
        }
    }

    func testKnownCommandsPresent() {
        let names = Set(SlashCommandRegistry.all.map(\.name))
        for expected in ["clear", "model", "effort", "memory", "plan", "help", "cost", "loop"] {
            XCTAssertTrue(names.contains(expected), "Expected /\(expected) in registry")
        }
    }

    // ── suggestions(for:) ────────────────────────────────────────────

    func testEmptyQueryReturnsAll() {
        XCTAssertEqual(SlashCommandRegistry.suggestions(for: "").count,
                       SlashCommandRegistry.all.count)
    }

    func testFilterByExactName() {
        let results = SlashCommandRegistry.suggestions(for: "model")
        XCTAssertTrue(results.contains(where: { $0.name == "model" }))
    }

    func testFilterByPartialName() {
        let results = SlashCommandRegistry.suggestions(for: "eff")
        XCTAssertTrue(results.contains(where: { $0.name == "effort" }))
    }

    func testFilterByDescriptionKeyword() {
        let results = SlashCommandRegistry.suggestions(for: "context")
        XCTAssertFalse(results.isEmpty)
    }

    func testFilterCaseInsensitive() {
        let lower = SlashCommandRegistry.suggestions(for: "model")
        let upper = SlashCommandRegistry.suggestions(for: "MODEL")
        XCTAssertEqual(lower.map(\.id).sorted(), upper.map(\.id).sorted())
    }

    func testNoMatchReturnsEmpty() {
        let results = SlashCommandRegistry.suggestions(for: "zzznomatch999")
        XCTAssertTrue(results.isEmpty)
    }

    // ── groupedSuggestions(for:) ──────────────────────────────────────

    func testGroupedSuggestionsPreservesGroupOrder() {
        let grouped = SlashCommandRegistry.groupedSuggestions(for: "")
        let returnedGroups = grouped.map(\.group)
        let expectedOrder = SlashCommandGroup.allCases.filter { group in
            SlashCommandRegistry.all.contains(where: { $0.group == group })
        }
        XCTAssertEqual(returnedGroups, expectedOrder)
    }

    func testGroupedSuggestionsOmitsEmptyGroups() {
        let grouped = SlashCommandRegistry.groupedSuggestions(for: "clear")
        // "clear" is in the session group; other groups should be absent
        for (group, cmds) in grouped {
            XCTAssertFalse(cmds.isEmpty, "Group \(group) returned with 0 commands")
        }
    }

    func testGroupedSuggestionsModelQueryReturnsModelGroup() {
        let grouped = SlashCommandRegistry.groupedSuggestions(for: "model")
        let modelGroup = grouped.first(where: { $0.group == .model })
        XCTAssertNotNil(modelGroup)
        XCTAssertTrue(modelGroup!.commands.contains(where: { $0.name == "model" }))
    }

    func testGroupedSuggestionsEmptyQueryAllGroupsPresent() {
        let grouped = SlashCommandRegistry.groupedSuggestions(for: "")
        let groups = Set(grouped.map(\.group))
        for g in SlashCommandGroup.allCases {
            if SlashCommandRegistry.all.contains(where: { $0.group == g }) {
                XCTAssertTrue(groups.contains(g), "Group \(g) missing from full groupedSuggestions")
            }
        }
    }
}

// MARK: - ChatSendRouting — new slash command parsing

final class ChatSendRoutingNewCommandsTests: XCTestCase {

    // ── Session commands ──────────────────────────────────────────────

    func testParseClear() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/clear"), .clear)
    }

    func testParseCompact() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/compact"), .compact)
    }

    func testParseExportWithFormat() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/export md"), .export(format: "md"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/export html"), .export(format: "html"))
    }

    func testParseExportWithoutFormat() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/export"), .export(format: nil))
    }

    func testParseResume() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/resume"), .resume)
    }

    // ── Model commands ────────────────────────────────────────────────

    func testParseModelWithArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/model claude-sonnet-4-6"), .model("claude-sonnet-4-6"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/model opus"), .model("opus"))
    }

    func testParseModelWithoutArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/model"), .model(nil))
    }

    func testParseEffortWithArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/effort low"), .effort("low"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/effort medium"), .effort("medium"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/effort high"), .effort("high"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/effort max"), .effort("max"))
    }

    func testParseEffortWithoutArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/effort"), .effort(nil))
    }

    func testParseFast() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/fast"), .fast)
    }

    // ── Memory & Skills ───────────────────────────────────────────────

    func testParseMemory() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/memory"), .memory)
    }

    func testParseSkills() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/skills"), .skills)
    }

    // ── Agents ────────────────────────────────────────────────────────

    func testParseModeWithArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/mode auto"), .mode("auto"))
    }

    func testParseModeWithoutArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/mode"), .mode(nil))
    }

    func testParsePlan() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/plan"), .plan)
    }

    // ── Tools ─────────────────────────────────────────────────────────

    func testParseMcp() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/mcp"), .mcp)
    }

    func testParsePermissions() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/permissions"), .permissions)
    }

    // ── Git ───────────────────────────────────────────────────────────

    func testParseReview() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/review"), .review)
    }

    func testParseDiff() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/diff"), .diff)
    }

    func testParseBranchWithArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/branch main"), .branch(action: "main"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/branch new feature-x"), .branch(action: "new feature-x"))
    }

    func testParseBranchWithoutArg() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/branch"), .branch(action: nil))
    }

    func testParseInit() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/init"), .initialize)
    }

    // ── Workflow ──────────────────────────────────────────────────────

    func testParseLoopWithInterval() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/loop 30"), .loop(interval: 30))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/loop 0"), .loop(interval: 0))
    }

    func testParseLoopWithoutInterval() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/loop"), .loop(interval: nil))
    }

    func testParseLoopNonNumericArgYieldsNilInterval() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/loop daily"), .loop(interval: nil))
    }

    func testParseSchedule() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/schedule"), .schedule)
    }

    // ── Info ──────────────────────────────────────────────────────────

    func testParseContext() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/context"), .context)
    }

    func testParseCost() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/cost"), .cost)
    }

    // ── Edge cases ────────────────────────────────────────────────────

    func testCommandParsingCaseInsensitive() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/CLEAR"), .clear)
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/Model opus"), .model("opus"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/EFFORT high"), .effort("high"))
    }

    func testMultilineUsesFirstLineForNewCommands() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/model sonnet\nignored line"), .model("sonnet"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/clear\nsome text"), .clear)
    }

    func testTrailingWhitespaceStripped() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("  /clear  "), .clear)
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("  /model sonnet  "), .model("sonnet"))
    }
}
