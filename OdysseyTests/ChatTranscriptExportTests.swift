import XCTest
import SwiftData
@testable import Odyssey

@MainActor
final class ChatTranscriptExportTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeConversationContext() throws -> (
        container: ModelContainer,
        context: ModelContext,
        conversation: Conversation,
        user: Participant,
        agentParticipant: Participant,
        agent: Agent,
        session: Session
    ) {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let agent = Agent(name: "Helper", icon: "cpu", color: "purple")
        ctx.insert(agent)

        let convo = Conversation(topic: "My Topic")
        let session = Session(agent: agent, workingDirectory: "/tmp")
        session.conversations = [convo]
        convo.sessions = [session]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants = (convo.participants ?? []) + [user]

        let agentPart = Participant(type: .agentSession(sessionId: session.id), displayName: agent.name)
        agentPart.conversation = convo
        convo.participants = (convo.participants ?? []) + [agentPart]

        ctx.insert(convo)
        ctx.insert(session)
        ctx.insert(user)
        ctx.insert(agentPart)

        return (container, ctx, convo, user, agentPart, agent, session)
    }

    private func makeTimestamps() -> (Date, Date) {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2025
        comps.month = 6
        comps.day = 15
        comps.hour = 10
        comps.minute = 30
        comps.second = 0
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        let t1 = cal.date(from: comps)!
        comps.minute = 31
        let t2 = cal.date(from: comps)!
        return (t1, t2)
    }

    func testMarkdownIncludesPortableAttachmentMetadataAndToolSections() throws {
        let (_, ctx, convo, user, agentPart, agent, _) = try makeConversationContext()
        let (t1, t2) = makeTimestamps()

        let mUser = ConversationMessage(senderParticipantId: user.id, text: "Hello ```world```", type: .chat, conversation: convo)
        mUser.timestamp = t1
        let att = MessageAttachment(mediaType: "image/png", fileName: "shot.png", fileSize: 100, message: mUser)
        mUser.attachments.append(att)

        let mTool = ConversationMessage(senderParticipantId: agentPart.id, text: "", type: .toolCall, conversation: convo)
        mTool.timestamp = t2
        mTool.toolName = "read_file"
        mTool.toolInput = "{\"path\":\"/tmp/a.txt\"}"

        let mResult = ConversationMessage(senderParticipantId: agentPart.id, text: "", type: .toolResult, conversation: convo)
        mResult.timestamp = t2
        mResult.toolName = "read_file"
        mResult.toolOutput = "contents"

        let mSys = ConversationMessage(senderParticipantId: nil, text: "Connected.", type: .system, conversation: convo)
        mSys.timestamp = t2

        convo.messages = [mUser, mTool, mResult, mSys]
        ctx.insert(mUser)
        ctx.insert(mTool)
        ctx.insert(mResult)
        ctx.insert(mSys)
        ctx.insert(att)

        let ordered = convo.messages.sorted { $0.timestamp < $1.timestamp }
        let snap = ChatTranscriptExport.snapshot(
            conversation: convo,
            messages: ordered,
            participants: convo.participants,
            streamingAppendix: nil
        )
        let md = ChatTranscriptExport.markdown(snap)

        XCTAssertTrue(md.contains("# My Topic"))
        XCTAssertTrue(md.contains("## You ·"))
        XCTAssertTrue(md.contains("Attachments:"))
        XCTAssertTrue(md.contains("- shot.png (image/png, 100 B)"))
        XCTAssertTrue(md.contains("Hello ``\\`world``\\`"))
        XCTAssertTrue(md.contains("## Tool call · \(agent.name) ·"))
        XCTAssertTrue(md.contains("read_file"))
        XCTAssertTrue(md.contains("```json"))
        XCTAssertTrue(md.contains("## Tool result · \(agent.name) ·"))
        XCTAssertTrue(md.contains("## System · System ·"))
        XCTAssertTrue(md.contains("Connected."))
    }

    func testHtmlRendersUserAndAgentBubbleMetadataWithMarkdown() {
        let userSender = ChatTranscriptSenderPresentation(displayName: "You", role: .user, iconName: nil, colorName: nil)
        let agentSender = ChatTranscriptSenderPresentation(displayName: "Helper", role: .agent, iconName: "cpu", colorName: "purple")
        let snap = ChatTranscriptSnapshot(
            title: "Styled",
            startedAtISO: "2025-01-01T00:00:00.000Z",
            rows: [
                .init(kind: .chat(
                    sender: userSender,
                    timestampISO: "2025-01-01T00:00:00.000Z",
                    text: "User message",
                    thinking: nil,
                    attachments: []
                )),
                .init(kind: .chat(
                    sender: agentSender,
                    timestampISO: "2025-01-01T00:01:00.000Z",
                    text: "## Heading\n\nSome [link](https://example.com) and `code`.",
                    thinking: "Reasoning block",
                    attachments: []
                ))
            ],
            streamingAppendix: nil,
            theme: .init(appearance: .light, textScale: 1.0)
        )

        let html = ChatTranscriptExport.html(snap)
        XCTAssertTrue(html.contains("bubble-user"))
        XCTAssertTrue(html.contains("bubble-agent"))
        XCTAssertTrue(html.contains("Helper"))
        XCTAssertTrue(html.contains("Heading"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">link</a>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
        XCTAssertTrue(html.contains("Thinking"))
    }

    func testHtmlRendersPipeTablesAsStructuredTables() {
        let sender = ChatTranscriptSenderPresentation(displayName: "Helper", role: .agent, iconName: "cpu", colorName: "purple")
        let snap = ChatTranscriptSnapshot(
            title: "Tables",
            startedAtISO: nil,
            rows: [
                .init(kind: .chat(
                    sender: sender,
                    timestampISO: "2025-01-01T00:01:00.000Z",
                    text: """
                    | Commit | Description |
                    | --- | --- |
                    | 1c84b36 | Initial MVP |
                    | 22d7af7 | Bug fixes |
                    """,
                    thinking: nil,
                    attachments: []
                ))
            ],
            streamingAppendix: nil,
            theme: .init(appearance: .light, textScale: 1.0)
        )

        let html = ChatTranscriptExport.html(snap)
        XCTAssertTrue(html.contains("<div class=\"table-wrap\">"))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>Commit</th>"))
        XCTAssertTrue(html.contains("<th>Description</th>"))
        XCTAssertTrue(html.contains("<td>1c84b36</td>"))
        XCTAssertTrue(html.contains("<td>Initial MVP</td>"))
        XCTAssertFalse(html.contains("| --- | --- |"))
    }

    func testHtmlRendersCardVariantsForToolsAndSystem() {
        let sender = ChatTranscriptSenderPresentation(displayName: "Helper", role: .agent, iconName: "cpu", colorName: "blue")
        let snap = ChatTranscriptSnapshot(
            title: "Cards",
            startedAtISO: nil,
            rows: [
                .init(kind: .toolCall(
                    sender: sender,
                    timestampISO: "2025-01-01T00:00:00.000Z",
                    toolName: "edit",
                    input: "{\"file\":\"a.swift\"}"
                )),
                .init(kind: .toolResult(
                    sender: sender,
                    timestampISO: "2025-01-01T00:01:00.000Z",
                    toolName: "edit",
                    output: "ok"
                )),
                .init(kind: .labeled(
                    category: .task,
                    kindLabel: "Task",
                    sender: sender,
                    timestampISO: "2025-01-01T00:02:00.000Z",
                    text: "Finished task",
                    richTextFormat: nil
                )),
                .init(kind: .labeled(
                    category: .system,
                    kindLabel: "System",
                    sender: .init(displayName: "System", role: .system, iconName: nil, colorName: nil),
                    timestampISO: "2025-01-01T00:03:00.000Z",
                    text: "Connected.",
                    richTextFormat: nil
                ))
            ],
            streamingAppendix: nil,
            theme: .init(appearance: .light, textScale: 1.0)
        )

        let html = ChatTranscriptExport.html(snap)
        XCTAssertTrue(html.contains("bubble-toolCall"))
        XCTAssertTrue(html.contains("bubble-toolResult"))
        XCTAssertTrue(html.contains("bubble-task"))
        XCTAssertTrue(html.contains("system-pill"))
        XCTAssertTrue(html.contains("Tool</span><code>edit</code>"))
    }

    func testHtmlRendersAttachmentPreviewAndFileCard() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("preview.png")
        try Data("fake-image".utf8).write(to: imageURL)

        let sender = ChatTranscriptSenderPresentation(displayName: "Helper", role: .agent, iconName: "cpu", colorName: "green")
        let snap = ChatTranscriptSnapshot(
            title: "Attachments",
            startedAtISO: nil,
            rows: [
                .init(kind: .chat(
                    sender: sender,
                    timestampISO: "2025-01-01T00:00:00.000Z",
                    text: "See attached.",
                    thinking: nil,
                    attachments: [
                        .init(fileName: "preview.png", mediaType: "image/png", fileSize: 10, localFilePath: imageURL.path),
                        .init(fileName: "report.pdf", mediaType: "application/pdf", fileSize: 2048, localFilePath: nil)
                    ]
                ))
            ],
            streamingAppendix: nil,
            theme: .init(appearance: .light, textScale: 1.0)
        )

        let html = ChatTranscriptExport.html(snap)
        XCTAssertTrue(html.contains("attachment-image"))
        XCTAssertTrue(html.contains("data:image/png;base64,"))
        XCTAssertTrue(html.contains("attachment-file"))
        XCTAssertTrue(html.contains("report.pdf"))
    }

    func testThemeAffectsHtmlOutput() {
        let row = ChatTranscriptSnapshot.Row(kind: .chat(
            sender: .init(displayName: "A & B", role: .agent, iconName: "cpu", colorName: "indigo"),
            timestampISO: "2025-01-01T00:00:00.000Z",
            text: "Line1\n\n<script>x</script>",
            thinking: nil,
            attachments: []
        ))

        let light = ChatTranscriptSnapshot(
            title: "T <itle>",
            startedAtISO: "2025-01-01T00:00:00.000Z",
            rows: [row],
            streamingAppendix: nil,
            theme: .init(appearance: .light, textScale: 1.12)
        )
        let dark = ChatTranscriptSnapshot(
            title: "T <itle>",
            startedAtISO: "2025-01-01T00:00:00.000Z",
            rows: [row],
            streamingAppendix: nil,
            theme: .init(appearance: .dark, textScale: 1.12)
        )

        let lightHTML = ChatTranscriptExport.html(light)
        let darkHTML = ChatTranscriptExport.html(dark)

        XCTAssertTrue(lightHTML.contains("<title>T &lt;itle&gt;</title>"))
        XCTAssertTrue(lightHTML.contains("A &amp; B"))
        XCTAssertTrue(lightHTML.contains("&lt;script&gt;"))
        XCTAssertFalse(lightHTML.contains("<script>x</script>"))
        XCTAssertTrue(lightHTML.contains("--canvas: #F6F7FB"))
        XCTAssertTrue(darkHTML.contains("--canvas: #0F1115"))
        XCTAssertTrue(lightHTML.contains("--text-scale: 1.120"))
    }

    func testHtmlFallsBackWhenSymbolIsUnavailable() {
        let snap = ChatTranscriptSnapshot(
            title: "Fallback",
            startedAtISO: nil,
            rows: [
                .init(kind: .chat(
                    sender: .init(displayName: "Broken", role: .agent, iconName: "definitely.not.a.symbol", colorName: "blue"),
                    timestampISO: "2025-01-01T00:00:00.000Z",
                    text: "Hello",
                    thinking: nil,
                    attachments: []
                ))
            ],
            streamingAppendix: nil,
            theme: .init(appearance: .light, textScale: 1.0)
        )

        let html = ChatTranscriptExport.html(snap)
        XCTAssertTrue(html.contains("icon-fallback"))
    }

    func testStreamingAppendixInMarkdownIncludesIconMetadataWhenPresent() {
        let snap = ChatTranscriptSnapshot(
            title: "Live",
            startedAtISO: nil,
            rows: [],
            streamingAppendix: ChatTranscriptStreamingAppendix(
                text: "typing…",
                thinking: "hmm",
                displayName: "Claude",
                iconName: "cpu",
                colorName: "blue"
            ),
            theme: .init(appearance: .light, textScale: 1.0)
        )
        let md = ChatTranscriptExport.markdown(snap)
        XCTAssertTrue(md.contains("In progress (not yet saved)"))
        XCTAssertTrue(md.contains("**Claude** `cpu`"))
        XCTAssertTrue(md.contains("typing…"))
        XCTAssertTrue(md.contains("hmm"))
    }

    func testEmptyTranscriptPlaceholder() {
        let snap = ChatTranscriptSnapshot(
            title: "Empty",
            startedAtISO: nil,
            rows: [],
            streamingAppendix: nil,
            theme: .init(appearance: .light, textScale: 1.0)
        )
        XCTAssertTrue(ChatTranscriptExport.markdown(snap).contains("No messages"))
        XCTAssertTrue(ChatTranscriptExport.html(snap).contains("No messages"))
    }
}
