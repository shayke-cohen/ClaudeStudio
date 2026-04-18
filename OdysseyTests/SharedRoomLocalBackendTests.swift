import CloudKit
import SwiftData
import XCTest
@testable import Odyssey

final class SharedRoomLocalRecordStoreTests: XCTestCase {
    private var storeURL: URL!
    private var store: SharedRoomLocalRecordStore!

    override func setUp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedRoomLocalRecordStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("records.plist")
        store = SharedRoomLocalRecordStore(storeURL: storeURL)
    }

    override func tearDown() async throws {
        if let directory = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
        store = nil
        storeURL = nil
    }

    func testSaveAndFetchRoundTrip() throws {
        let record = CKRecord(recordType: "Room", recordID: .init(recordName: "room-1"))
        record["roomId"] = "room-1" as CKRecordValue
        record["topic"] = "API Room" as CKRecordValue
        record["membershipVersion"] = 2 as CKRecordValue

        _ = try store.save(record: record)
        let fetched = try store.fetchRecord(recordName: "room-1")

        XCTAssertEqual(fetched.recordType, "Room")
        XCTAssertEqual(fetched["roomId"] as? String, "room-1")
        XCTAssertEqual(fetched["topic"] as? String, "API Room")
        XCTAssertEqual(fetched["membershipVersion"] as? Int, 2)
    }

    func testQueryFiltersAndSortsMessages() throws {
        let first = CKRecord(recordType: "RoomMessage", recordID: .init(recordName: "message-room-1-a"))
        first["roomId"] = "room-1" as CKRecordValue
        first["hostSequence"] = 20 as CKRecordValue
        first["text"] = "second" as CKRecordValue
        first["createdAt"] = Date(timeIntervalSince1970: 20) as CKRecordValue

        let second = CKRecord(recordType: "RoomMessage", recordID: .init(recordName: "message-room-1-b"))
        second["roomId"] = "room-1" as CKRecordValue
        second["hostSequence"] = 10 as CKRecordValue
        second["text"] = "first" as CKRecordValue
        second["createdAt"] = Date(timeIntervalSince1970: 10) as CKRecordValue

        let otherRoom = CKRecord(recordType: "RoomMessage", recordID: .init(recordName: "message-room-2"))
        otherRoom["roomId"] = "room-2" as CKRecordValue
        otherRoom["hostSequence"] = 1 as CKRecordValue
        otherRoom["text"] = "ignored" as CKRecordValue
        otherRoom["createdAt"] = Date(timeIntervalSince1970: 1) as CKRecordValue

        _ = try store.save(record: first)
        _ = try store.save(record: second)
        _ = try store.save(record: otherRoom)

        let records = try store.queryRecords(
            recordType: "RoomMessage",
            predicate: NSPredicate(format: "roomId == %@", "room-1"),
            sortDescriptors: [NSSortDescriptor(key: "hostSequence", ascending: true)]
        )

        XCTAssertEqual(records.map { $0["text"] as? String }, ["first", "second"])
    }

    func testQuerySupportsInviteInboxPredicate() throws {
        let targeted = CKRecord(recordType: "RoomInvite", recordID: .init(recordName: "invite-targeted"))
        targeted["inviteId"] = "invite-targeted" as CKRecordValue
        targeted["recipientLabel"] = "Guest" as CKRecordValue

        let openInvite = CKRecord(recordType: "RoomInvite", recordID: .init(recordName: "invite-open"))
        openInvite["inviteId"] = "invite-open" as CKRecordValue

        let otherInvite = CKRecord(recordType: "RoomInvite", recordID: .init(recordName: "invite-other"))
        otherInvite["inviteId"] = "invite-other" as CKRecordValue
        otherInvite["recipientLabel"] = "Someone Else" as CKRecordValue

        _ = try store.save(record: targeted)
        _ = try store.save(record: openInvite)
        _ = try store.save(record: otherInvite)

        let records = try store.queryRecords(
            recordType: "RoomInvite",
            predicate: NSPredicate(format: "recipientLabel == %@ OR recipientLabel == nil", "Guest"),
            sortDescriptors: []
        )

        XCTAssertEqual(Set(records.map { $0["inviteId"] as? String ?? "" }), Set(["invite-targeted", "invite-open"]))
    }
}

@MainActor
final class SharedRoomServiceLocalBackendTests: XCTestCase {
    private var storeURL: URL!
    private var hostContainer: ModelContainer!
    private var guestContainer: ModelContainer!
    private var hostService: SharedRoomService!
    private var guestService: SharedRoomService!

    override func setUp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedRoomServiceLocalBackendTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("records.plist")

        setenv("ODYSSEY_SHARED_ROOM_BACKEND", "local-test", 1)
        setenv("ODYSSEY_SHARED_ROOM_STORE_PATH", storeURL.path, 1)

        hostContainer = try Self.makeContainer()
        guestContainer = try Self.makeContainer()

        hostService = SharedRoomService()
        guestService = SharedRoomService()
        hostService.configure(modelContext: hostContainer.mainContext)
        guestService.configure(modelContext: guestContainer.mainContext)
    }

    override func tearDown() async throws {
        unsetenv("ODYSSEY_SHARED_ROOM_BACKEND")
        unsetenv("ODYSSEY_SHARED_ROOM_STORE_PATH")
        InstanceConfig.userDefaults.removeObject(forKey: AppSettings.sharedRoomUserIdKey)
        InstanceConfig.userDefaults.removeObject(forKey: AppSettings.sharedRoomDisplayNameKey)
        if let directory = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
        hostService = nil
        guestService = nil
        hostContainer = nil
        guestContainer = nil
        storeURL = nil
    }

    func testHostGuestCanShareRoomAndMessagesViaLocalBackend() async throws {
        setIdentity(userId: "host-user", displayName: "Host User")
        let hostConversation = try await hostService.createLocalTestRoom(topic: "API Shared Room")
        let invite = try await hostService.createInvite(
            for: hostConversation,
            recipientLabel: "Guest User",
            expiresIn: 3600,
            singleUse: true
        )

        setIdentity(userId: "guest-user", displayName: "Guest User")
        let guestConversation = try await guestService.acceptInvite(
            roomId: hostConversation.roomId ?? "",
            inviteId: invite.inviteId,
            inviteToken: invite.inviteToken,
            projectId: nil
        )
        XCTAssertEqual(guestConversation.roomId, hostConversation.roomId)

        setIdentity(userId: "host-user", displayName: "Host User")
        _ = try await hostService.sendLocalUserMessage(
            text: "hello from host",
            roomId: hostConversation.roomId ?? ""
        )

        setIdentity(userId: "guest-user", displayName: "Guest User")
        try await guestService.refreshRoom(roomId: guestConversation.roomId ?? "")
        let guestSnapshot = try XCTUnwrap(guestService.roomSnapshot(roomId: guestConversation.roomId ?? ""))
        XCTAssertTrue(guestSnapshot.messages.contains(where: { $0.text == "hello from host" }))
        XCTAssertTrue(guestSnapshot.participants.contains(where: { $0.displayName == "Host User" }))
        XCTAssertTrue(guestSnapshot.participants.contains(where: { $0.displayName == "Guest User" }))

        _ = try await guestService.sendLocalUserMessage(
            text: "hello from guest",
            roomId: guestConversation.roomId ?? ""
        )

        setIdentity(userId: "host-user", displayName: "Host User")
        try await hostService.refreshRoom(roomId: hostConversation.roomId ?? "")
        let hostSnapshot = try XCTUnwrap(hostService.roomSnapshot(roomId: hostConversation.roomId ?? ""))
        XCTAssertTrue(hostSnapshot.messages.contains(where: { $0.text == "hello from guest" }))

        setIdentity(userId: "guest-user", displayName: "Guest User")
        do {
            _ = try await guestService.acceptInvite(
                roomId: hostConversation.roomId ?? "",
                inviteId: invite.inviteId,
                inviteToken: invite.inviteToken,
                projectId: nil
            )
            XCTFail("Expected single-use invite reuse to throw")
        } catch {
        }
    }

    private func setIdentity(userId: String, displayName: String) {
        InstanceConfig.userDefaults.set(userId, forKey: AppSettings.sharedRoomUserIdKey)
        InstanceConfig.userDefaults.set(displayName, forKey: AppSettings.sharedRoomDisplayNameKey)
    }

    private static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self,
            Agent.self,
            Session.self,
            Conversation.self,
            Participant.self,
            ConversationMessage.self,
            MessageAttachment.self,
            Skill.self,
            MCPServer.self,
            PermissionSet.self,
            SharedWorkspace.self,
            BlackboardEntry.self,
            Peer.self,
            AgentGroup.self,
            ScheduledMission.self,
            ScheduledMissionRun.self,
            SharedRoomInvite.self,
            configurations: config
        )
    }
}
