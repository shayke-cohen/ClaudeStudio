import XCTest
@testable import ClaudPeer

final class RichChatComponentTests: XCTestCase {

    // MARK: - Admonition Parser

    func testAdmonitionParserExtractsInfoBlock() {
        let text = """
        Some intro text.

        > [!info] Important Note
        > This is an info callout.
        > It spans multiple lines.

        More text after.
        """
        let blocks = AdmonitionParser.extractBlocks(from: text)
        XCTAssertNotNil(blocks)
        XCTAssertEqual(blocks?.count, 3)

        if case .markdown(let md) = blocks?[0] {
            XCTAssertTrue(md.contains("Some intro text"))
        } else {
            XCTFail("Expected markdown block first")
        }

        if case .admonition(let kind, let title, let body) = blocks?[1] {
            XCTAssertEqual(kind, .info)
            XCTAssertEqual(title, "Important Note")
            XCTAssertTrue(body.contains("This is an info callout"))
            XCTAssertTrue(body.contains("It spans multiple lines"))
        } else {
            XCTFail("Expected admonition block")
        }

        if case .markdown(let md) = blocks?[2] {
            XCTAssertTrue(md.contains("More text after"))
        } else {
            XCTFail("Expected trailing markdown block")
        }
    }

    func testAdmonitionParserHandlesMultipleTypes() {
        let text = """
        > [!success] Tests passed
        > All 42 tests passed.

        > [!warning] Missing coverage
        > Some files need tests.

        > [!error] Build failed
        > Fix the errors.
        """
        let blocks = AdmonitionParser.extractBlocks(from: text)
        XCTAssertNotNil(blocks)

        let admonitions = blocks?.compactMap { block -> AdmonitionKind? in
            if case .admonition(let kind, _, _) = block { return kind }
            return nil
        }
        XCTAssertEqual(admonitions, [.success, .warning, .error])
    }

    func testAdmonitionParserReturnsNilForPlainText() {
        let text = "Just a regular paragraph with no admonitions."
        let blocks = AdmonitionParser.extractBlocks(from: text)
        XCTAssertNil(blocks)
    }

    func testAdmonitionParserHandlesNoTitle() {
        let text = """
        > [!tip]
        > A useful tip.
        """
        let blocks = AdmonitionParser.extractBlocks(from: text)
        XCTAssertNotNil(blocks)

        if case .admonition(let kind, let title, let body) = blocks?.first {
            XCTAssertEqual(kind, .tip)
            XCTAssertEqual(title, "")
            XCTAssertTrue(body.contains("A useful tip"))
        } else {
            XCTFail("Expected admonition block")
        }
    }

    // MARK: - Admonition Kind

    func testAdmonitionKindProperties() {
        XCTAssertEqual(AdmonitionKind.success.defaultTitle, "Success")
        XCTAssertEqual(AdmonitionKind.warning.defaultTitle, "Warning")
        XCTAssertEqual(AdmonitionKind.error.icon, "xmark.circle.fill")
        XCTAssertEqual(AdmonitionKind.info.icon, "info.circle.fill")
        XCTAssertEqual(AdmonitionKind.tip.icon, "lightbulb.fill")
    }

    // MARK: - InlineDiffView Helpers

    func testInlineDiffViewFromEditToolCallParsesJSON() {
        let msg = ConversationMessage(
            senderParticipantId: nil,
            text: "",
            type: .toolCall
        )
        msg.toolName = "Edit"
        msg.toolInput = """
        {"file_path":"/tmp/test.swift","old_string":"let x = 1","new_string":"let x = 2"}
        """
        let diff = InlineDiffView.fromEditToolCall(msg)
        XCTAssertNotNil(diff)
    }

    func testInlineDiffViewReturnsNilForBadJSON() {
        let msg = ConversationMessage(
            senderParticipantId: nil,
            text: "",
            type: .toolCall
        )
        msg.toolName = "Edit"
        msg.toolInput = "not json"
        let diff = InlineDiffView.fromEditToolCall(msg)
        XCTAssertNil(diff)
    }

    func testInlineDiffViewReturnsNilForMissingFields() {
        let msg = ConversationMessage(
            senderParticipantId: nil,
            text: "",
            type: .toolCall
        )
        msg.toolName = "Edit"
        msg.toolInput = """
        {"file_path":"/tmp/test.swift"}
        """
        let diff = InlineDiffView.fromEditToolCall(msg)
        XCTAssertNil(diff)
    }

    // MARK: - TerminalOutputView Helpers

    func testTerminalOutputFromBashToolCallParsesCommand() {
        let term = TerminalOutputView.fromBashToolCall(
            input: """
            {"command":"echo hello"}
            """,
            output: "hello\n"
        )
        XCTAssertNotNil(term)
        XCTAssertEqual(term?.command, "echo hello")
        XCTAssertEqual(term?.output, "hello\n")
    }

    func testTerminalOutputFromBashToolCallPlainString() {
        let term = TerminalOutputView.fromBashToolCall(
            input: "ls -la",
            output: "total 0"
        )
        XCTAssertNotNil(term)
        XCTAssertEqual(term?.command, "ls -la")
    }

    func testTerminalOutputReturnsNilForNilInput() {
        let term = TerminalOutputView.fromBashToolCall(input: nil, output: "hello")
        XCTAssertNil(term)
    }

    // MARK: - Wire Protocol: New Event Decoding

    func testAgentConfirmationDecoding() throws {
        let jsonStr = """
        {"type":"agent.confirmation","sessionId":"s1","confirmationId":"c1","action":"git push","reason":"pushing to main","riskLevel":"high","details":"3 files changed"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .agentConfirmation(let sid, let cid, let action, let reason, let risk, let details) = event {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(cid, "c1")
            XCTAssertEqual(action, "git push")
            XCTAssertEqual(reason, "pushing to main")
            XCTAssertEqual(risk, "high")
            XCTAssertEqual(details, "3 files changed")
        } else {
            XCTFail("Expected .agentConfirmation, got \(String(describing: event))")
        }
    }

    func testStreamRichContentDecoding() throws {
        let jsonStr = """
        {"type":"stream.richContent","sessionId":"s1","format":"html","title":"Report","content":"<h1>Hello</h1>","height":300}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .streamRichContent(let sid, let format, let title, let content, let height) = event {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(format, "html")
            XCTAssertEqual(title, "Report")
            XCTAssertEqual(content, "<h1>Hello</h1>")
            XCTAssertEqual(height, 300)
        } else {
            XCTFail("Expected .streamRichContent, got \(String(describing: event))")
        }
    }

    func testStreamProgressDecoding() throws {
        let jsonStr = """
        {"type":"stream.progress","sessionId":"s1","progressId":"p1","title":"Building","steps":[{"label":"Compile","status":"done"},{"label":"Test","status":"running"}]}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .streamProgress(let sid, let pid, let title, let steps) = event {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(pid, "p1")
            XCTAssertEqual(title, "Building")
            XCTAssertEqual(steps.count, 2)
            XCTAssertEqual(steps[0].label, "Compile")
            XCTAssertEqual(steps[0].status, "done")
            XCTAssertEqual(steps[1].label, "Test")
            XCTAssertEqual(steps[1].status, "running")
        } else {
            XCTFail("Expected .streamProgress, got \(String(describing: event))")
        }
    }

    func testStreamSuggestionsDecoding() throws {
        let jsonStr = """
        {"type":"stream.suggestions","sessionId":"s1","suggestions":[{"label":"Run tests","message":"run all tests"},{"label":"Show diff"}]}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .streamSuggestions(let sid, let suggestions) = event {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(suggestions.count, 2)
            XCTAssertEqual(suggestions[0].label, "Run tests")
            XCTAssertEqual(suggestions[0].message, "run all tests")
            XCTAssertEqual(suggestions[1].label, "Show diff")
            XCTAssertNil(suggestions[1].message)
        } else {
            XCTFail("Expected .streamSuggestions, got \(String(describing: event))")
        }
    }

    // MARK: - Wire Protocol: New Command Encoding

    func testConfirmationAnswerEncoding() throws {
        let command = SidecarCommand.confirmationAnswer(
            sessionId: "s1",
            confirmationId: "c1",
            approved: true,
            modifiedAction: "git push --dry-run"
        )
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.confirmationAnswer")
        XCTAssertEqual(json["sessionId"] as? String, "s1")
        XCTAssertEqual(json["confirmationId"] as? String, "c1")
        XCTAssertEqual(json["approved"] as? Bool, true)
        XCTAssertEqual(json["modifiedAction"] as? String, "git push --dry-run")
    }

    func testConfirmationAnswerEncodingRejected() throws {
        let command = SidecarCommand.confirmationAnswer(
            sessionId: "s1",
            confirmationId: "c1",
            approved: false,
            modifiedAction: nil
        )
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["approved"] as? Bool, false)
        XCTAssertNil(json["modifiedAction"] as? String)
    }

    // MARK: - Settings Keys

    func testChatDisplaySettingsKeysExist() {
        XCTAssertEqual(AppSettings.renderMermaidKey, "claudpeer.chat.renderMermaid")
        XCTAssertEqual(AppSettings.renderHTMLKey, "claudpeer.chat.renderHTML")
        XCTAssertEqual(AppSettings.renderDiffsKey, "claudpeer.chat.renderDiffs")
        XCTAssertEqual(AppSettings.renderTerminalKey, "claudpeer.chat.renderTerminal")
        XCTAssertEqual(AppSettings.renderAdmonitionsKey, "claudpeer.chat.renderAdmonitions")
        XCTAssertEqual(AppSettings.renderPDFKey, "claudpeer.chat.renderPDF")
        XCTAssertEqual(AppSettings.showSessionSummaryKey, "claudpeer.chat.showSessionSummary")
        XCTAssertEqual(AppSettings.showSuggestionChipsKey, "claudpeer.chat.showSuggestionChips")
    }

    func testChatDisplayKeysInAllKeys() {
        let allKeys = AppSettings.allKeys
        XCTAssertTrue(allKeys.contains(AppSettings.renderMermaidKey))
        XCTAssertTrue(allKeys.contains(AppSettings.renderDiffsKey))
        XCTAssertTrue(allKeys.contains(AppSettings.renderTerminalKey))
        XCTAssertTrue(allKeys.contains(AppSettings.showSessionSummaryKey))
    }

    // MARK: - MessageType

    func testRichContentMessageType() {
        let type = MessageType.richContent
        XCTAssertEqual(type.rawValue, "richContent")
    }
}
