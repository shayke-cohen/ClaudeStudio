import Foundation
import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class SidebarConversationMetadataTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self,
            ConversationMessage.self, MessageAttachment.self,
            Participant.self, Skill.self, Connection.self, MCPServer.self,
            PermissionSet.self, BlackboardEntry.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Helpers

    private func makeConversation() -> Conversation {
        let conv = Conversation(topic: "Test")
        context.insert(conv)
        return conv
    }

    private func addMessage(to conv: Conversation, text: String, offsetSeconds: TimeInterval) -> ConversationMessage {
        let msg = ConversationMessage(text: text, type: .chat, conversation: conv)
        msg.timestamp = Date(timeIntervalSince1970: 1_000_000 + offsetSeconds)
        context.insert(msg)
        return msg
    }

    // MARK: - lastMessagePreview

    func testLastMessagePreview_returnsLatestByTimestamp() throws {
        let conv = makeConversation()
        addMessage(to: conv, text: "first", offsetSeconds: 0)
        addMessage(to: conv, text: "second", offsetSeconds: 100)
        addMessage(to: conv, text: "last message", offsetSeconds: 200)
        try context.save()

        let preview = SidebarConversationMetadata.lastMessagePreview(conv)
        XCTAssertNotNil(preview)
        XCTAssertEqual(preview?.text, "last message")
    }

    func testLastMessagePreview_outOfOrderMessages_stillReturnsLatest() throws {
        let conv = makeConversation()
        // Insert in reverse timestamp order
        addMessage(to: conv, text: "newest", offsetSeconds: 300)
        addMessage(to: conv, text: "oldest", offsetSeconds: 0)
        addMessage(to: conv, text: "middle", offsetSeconds: 150)
        try context.save()

        let preview = SidebarConversationMetadata.lastMessagePreview(conv)
        XCTAssertEqual(preview?.text, "newest")
    }

    func testLastMessagePreview_emptyConversation_returnsNil() throws {
        let conv = makeConversation()
        try context.save()

        let preview = SidebarConversationMetadata.lastMessagePreview(conv)
        XCTAssertNil(preview)
    }

    func testLastMessagePreview_singleMessage() throws {
        let conv = makeConversation()
        addMessage(to: conv, text: "only message", offsetSeconds: 0)
        try context.save()

        let preview = SidebarConversationMetadata.lastMessagePreview(conv)
        XCTAssertEqual(preview?.text, "only message")
        XCTAssertNil(preview?.attachmentIcon)
    }

    func testLastMessagePreview_longTextIsTruncated() throws {
        let conv = makeConversation()
        let longText = String(repeating: "x", count: 80)
        addMessage(to: conv, text: longText, offsetSeconds: 0)
        try context.save()

        let preview = SidebarConversationMetadata.lastMessagePreview(conv)
        XCTAssertNotNil(preview)
        // Truncates at 40 chars + "..."
        XCTAssertTrue(preview!.text.hasSuffix("..."))
        XCTAssertEqual(preview!.text.count, 43)
    }

    func testLastMessagePreview_shortTextIsNotTruncated() throws {
        let conv = makeConversation()
        addMessage(to: conv, text: "hello", offsetSeconds: 0)
        try context.save()

        let preview = SidebarConversationMetadata.lastMessagePreview(conv)
        XCTAssertEqual(preview?.text, "hello")
    }

    func testLastMessagePreview_twoMessages_identicalTimestamp_returnsOne() throws {
        let conv = makeConversation()
        addMessage(to: conv, text: "alpha", offsetSeconds: 0)
        addMessage(to: conv, text: "beta", offsetSeconds: 0)
        try context.save()

        // With identical timestamps, max returns one of them (stable)
        let preview = SidebarConversationMetadata.lastMessagePreview(conv)
        XCTAssertNotNil(preview)
    }
}
