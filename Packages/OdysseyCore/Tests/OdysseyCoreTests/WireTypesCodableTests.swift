// Tests/OdysseyCoreTests/WireTypesCodableTests.swift
import XCTest
@testable import OdysseyCore

final class WireTypesCodableTests: XCTestCase {

    func testConversationSummaryWireCodableRoundTrip() throws {
        let participants = [
            ParticipantWire(id: "p1", displayName: "Alice", isAgent: false, isLocal: true),
            ParticipantWire(id: "p2", displayName: "Coder", isAgent: true, isLocal: false),
        ]
        let original = ConversationSummaryWire(
            id: "conv-abc",
            topic: "Build the feature",
            lastMessageAt: "2026-04-13T10:00:00Z",
            lastMessagePreview: "Sure, I'll start now.",
            unread: false,
            participants: participants,
            projectId: "proj-1",
            projectName: "Odyssey",
            workingDirectory: "/Users/alice/Odyssey"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConversationSummaryWire.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.topic, original.topic)
        XCTAssertEqual(decoded.lastMessageAt, original.lastMessageAt)
        XCTAssertEqual(decoded.lastMessagePreview, original.lastMessagePreview)
        XCTAssertEqual(decoded.unread, original.unread)
        XCTAssertEqual(decoded.participants.count, 2)
        XCTAssertEqual(decoded.participants[0].id, "p1")
        XCTAssertEqual(decoded.participants[1].isAgent, true)
        XCTAssertEqual(decoded.projectId, "proj-1")
        XCTAssertEqual(decoded.projectName, "Odyssey")
        XCTAssertEqual(decoded.workingDirectory, "/Users/alice/Odyssey")
    }

    func testConversationSummaryWireOptionalFieldsNil() throws {
        let original = ConversationSummaryWire(
            id: "conv-xyz",
            topic: "Untitled",
            lastMessageAt: "2026-04-13T11:00:00Z",
            lastMessagePreview: "",
            unread: true,
            participants: [],
            projectId: nil,
            projectName: nil,
            workingDirectory: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConversationSummaryWire.self, from: data)
        XCTAssertNil(decoded.projectId)
        XCTAssertNil(decoded.projectName)
        XCTAssertNil(decoded.workingDirectory)
    }

    func testMessageWireCodableRoundTrip() throws {
        let original = MessageWire(
            id: "msg-001",
            text: "Hello from the agent!",
            type: "chat",
            senderParticipantId: "p2",
            timestamp: "2026-04-13T10:01:00Z",
            isStreaming: false,
            toolName: nil,
            toolOutput: nil,
            thinkingText: "Let me think about this..."
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MessageWire.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.type, "chat")
        XCTAssertEqual(decoded.senderParticipantId, "p2")
        XCTAssertFalse(decoded.isStreaming)
        XCTAssertNil(decoded.toolName)
        XCTAssertEqual(decoded.thinkingText, "Let me think about this...")
    }

    func testMessageWireToolCallRoundTrip() throws {
        let original = MessageWire(
            id: "msg-002",
            text: "{\"command\": \"ls\"}",
            type: "toolCall",
            senderParticipantId: "p2",
            timestamp: "2026-04-13T10:02:00Z",
            isStreaming: false,
            toolName: "bash",
            toolOutput: "file1.swift\nfile2.swift",
            thinkingText: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MessageWire.self, from: data)
        XCTAssertEqual(decoded.toolName, "bash")
        XCTAssertEqual(decoded.toolOutput, "file1.swift\nfile2.swift")
        XCTAssertNil(decoded.thinkingText)
    }

    func testProjectSummaryWireCodableRoundTrip() throws {
        let original = ProjectSummaryWire(
            id: "proj-1",
            name: "Odyssey",
            rootPath: "/Users/alice/Odyssey",
            icon: "cpu",
            color: "purple",
            isPinned: true,
            pinnedAgentIds: ["agent-coder", "agent-reviewer"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectSummaryWire.self, from: data)
        XCTAssertEqual(decoded.id, "proj-1")
        XCTAssertEqual(decoded.name, "Odyssey")
        XCTAssertEqual(decoded.isPinned, true)
        XCTAssertEqual(decoded.pinnedAgentIds, ["agent-coder", "agent-reviewer"])
    }

    func testInvitePayloadCodableRoundTrip() throws {
        let turn = TURNConfig(url: "turn:relay.example.com:3478", username: "user", credential: "pass")
        let hints = InviteHints(lan: "192.168.1.42:9849", wan: "203.0.113.7:49152", turn: turn)
        let original = InvitePayload(
            v: 1,
            type: "device",
            userPublicKey: "abc123",
            displayName: "Alice",
            tlsCertDER: "MIIC...",
            wsToken: "tok_xyz",
            wsPort: 9849,
            hints: hints,
            exp: 9999999999,
            singleUse: true,
            sig: "sig_base64"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InvitePayload.self, from: data)
        XCTAssertEqual(decoded.userPublicKey, "abc123")
        XCTAssertEqual(decoded.displayName, "Alice")
        XCTAssertEqual(decoded.wsPort, 9849)
        XCTAssertEqual(decoded.hints.lan, "192.168.1.42:9849")
        XCTAssertEqual(decoded.hints.wan, "203.0.113.7:49152")
        XCTAssertEqual(decoded.hints.turn?.url, "turn:relay.example.com:3478")
        XCTAssertEqual(decoded.exp, 9999999999)
    }

    func testUserIdentityCodableRoundTrip() throws {
        let original = UserIdentity(
            publicKeyBase64url: "AAABBBCCC",
            displayName: "Alice",
            nodeId: "550e8400-e29b-41d4-a716-446655440000"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserIdentity.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testAgentIdentityBundleCodableRoundTrip() throws {
        let original = AgentIdentityBundle(
            agentName: "CodeReviewer",
            publicKeyBase64url: "XYZ987base64url",
            createdAt: "2026-04-13T09:00:00Z"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentIdentityBundle.self, from: data)
        XCTAssertEqual(decoded.agentName, original.agentName)
        XCTAssertEqual(decoded.publicKeyBase64url, original.publicKeyBase64url)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
    }

    func testTLSBundleCodableRoundTrip() throws {
        let original = TLSBundle(
            certDERBase64: "MIICpDCCAYwCCQD...",
            expiresAt: "2027-04-13T00:00:00Z"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TLSBundle.self, from: data)
        XCTAssertEqual(decoded.certDERBase64, original.certDERBase64)
        XCTAssertEqual(decoded.expiresAt, original.expiresAt)
    }
}
