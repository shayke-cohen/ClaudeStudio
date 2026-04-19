import Foundation
import CloudKit
import Security
import SwiftData
import OdysseyCore

@MainActor
final class SharedRoomService: ObservableObject {
    static let roomRecordType = "Room"
    static let inviteRecordType = "RoomInvite"
    static let membershipRecordType = "RoomMembership"
    static let messageRecordType = "RoomMessage"

    struct JoinPayload: Sendable, Equatable {
        let roomId: String
        let inviteId: String
        let inviteToken: String?
    }

    struct UserIdentity: Sendable, Equatable {
        let userId: String
        let displayName: String
        let nodeId: String
    }

    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var unreadInviteCount = 0

    private var modelContext: ModelContext?
    weak var p2pNetworkManager: P2PNetworkManager?
    private let localRecordStore: SharedRoomLocalRecordStore?
    private let cloudKitContainerIdentifier: String?
    private lazy var cloudDatabase: CKDatabase? = {
        guard let cloudKitContainerIdentifier else { return nil }
        return CKContainer(identifier: cloudKitContainerIdentifier).publicCloudDatabase
    }()
    private var syncTask: Task<Void, Never>?

    init() {
        self.localRecordStore = Self.makeLocalRecordStore()
        self.cloudKitContainerIdentifier = localRecordStore == nil ? Self.resolveCloudKitContainerIdentifier() : nil
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        unreadInviteCount = pendingInviteCount()
        if syncTask == nil, isSharedRoomBackendAvailable {
            startBackgroundSync()
        }
    }

    deinit {
        syncTask?.cancel()
    }

    func currentUserIdentity() -> UserIdentity {
        let defaults = InstanceConfig.userDefaults
        let userId: String
        if let existing = defaults.string(forKey: AppSettings.sharedRoomUserIdKey), !existing.isEmpty {
            userId = existing
        } else {
            userId = UUID().uuidString
            defaults.set(userId, forKey: AppSettings.sharedRoomUserIdKey)
        }

        let displayName = {
            let raw = defaults.string(forKey: AppSettings.sharedRoomDisplayNameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let raw, !raw.isEmpty { return raw }
            let candidate = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty { return candidate }
            return Host.current().localizedName ?? "Odyssey User"
        }()
        defaults.set(displayName, forKey: AppSettings.sharedRoomDisplayNameKey)

        let nodeId = "\(Host.current().localizedName ?? "Mac")-\(InstanceConfig.name)"
        return UserIdentity(userId: userId, displayName: displayName, nodeId: nodeId)
    }

    func createSharedRoom(for conversation: Conversation) async throws {
        guard isSharedRoomBackendAvailable else {
            throw SharedRoomError.cloudKitUnavailable
        }
        let identity = currentUserIdentity()
        ensureConversationRoomMetadata(conversation, role: .host, ownerUserId: identity.userId)
        let localUser = ensureLocalUserParticipant(in: conversation, identity: identity)
        localUser.membershipStatus = .active
        try? modelContext?.save()

        let roomRecord = CKRecord(
            recordType: Self.roomRecordType,
            recordID: CKRecord.ID(recordName: roomRecordName(roomId: conversation.roomId ?? ""))
        )
        roomRecord["roomId"] = conversation.roomId as CKRecordValue?
        roomRecord["topic"] = (conversation.topic ?? "Shared Room") as CKRecordValue
        roomRecord["ownerUserId"] = identity.userId as CKRecordValue
        roomRecord["ownerDisplayName"] = identity.displayName as CKRecordValue
        roomRecord["status"] = conversation.roomStatus.rawValue as CKRecordValue
        roomRecord["membershipVersion"] = conversation.roomMembershipVersion as CKRecordValue
        roomRecord["updatedAt"] = Date() as CKRecordValue
        _ = try await save(record: roomRecord)

        try await publishParticipant(localUser, in: conversation)
        try await refreshConversation(conversation)
    }

    func createInvite(
        for conversation: Conversation,
        recipientLabel: String?,
        expiresIn: TimeInterval = 24 * 60 * 60,
        singleUse: Bool = true
    ) async throws -> SharedRoomInvite {
        guard isSharedRoomBackendAvailable else {
            throw SharedRoomError.cloudKitUnavailable
        }
        if !conversation.isSharedRoom {
            try await createSharedRoom(for: conversation)
        }

        let identity = currentUserIdentity()
        let inviteId = UUID().uuidString
        let inviteToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let expiresAt = Date().addingTimeInterval(expiresIn)
        let roomId = conversation.roomId ?? UUID().uuidString
        let deepLink = "odyssey://room/join?roomId=\(roomId)&inviteId=\(inviteId)&token=\(inviteToken)"

        let inviteRecord = CKRecord(
            recordType: Self.inviteRecordType,
            recordID: CKRecord.ID(recordName: inviteRecordName(inviteId: inviteId))
        )
        inviteRecord["inviteId"] = inviteId as CKRecordValue
        inviteRecord["inviteToken"] = inviteToken as CKRecordValue
        inviteRecord["roomId"] = roomId as CKRecordValue
        inviteRecord["roomTopic"] = (conversation.topic ?? "Shared Room") as CKRecordValue
        inviteRecord["inviterUserId"] = identity.userId as CKRecordValue
        inviteRecord["inviterDisplayName"] = identity.displayName as CKRecordValue
        if let recipientLabel, !recipientLabel.isEmpty {
            inviteRecord["recipientLabel"] = recipientLabel as CKRecordValue
        }
        inviteRecord["deepLink"] = deepLink as CKRecordValue
        inviteRecord["expiresAt"] = expiresAt as CKRecordValue
        inviteRecord["singleUse"] = singleUse as CKRecordValue
        inviteRecord["isRevoked"] = false as CKRecordValue
        inviteRecord["status"] = SharedRoomInviteStatus.pending.rawValue as CKRecordValue
        inviteRecord["updatedAt"] = Date() as CKRecordValue
        _ = try await save(record: inviteRecord)

        let invite = upsertLocalInvite(from: inviteRecord)
        unreadInviteCount = pendingInviteCount()
        return invite
    }

    func acceptInvite(
        roomId: String,
        inviteId: String,
        inviteToken: String?,
        projectId: UUID?
    ) async throws -> Conversation {
        guard isSharedRoomBackendAvailable else {
            throw SharedRoomError.cloudKitUnavailable
        }
        let inviteRecord = try await fetchRecord(recordName: inviteRecordName(inviteId: inviteId))
        let recordRoomId = inviteRecord["roomId"] as? String
        guard recordRoomId == roomId else {
            throw SharedRoomError.invalidInvite
        }
        let expectedToken = inviteRecord["inviteToken"] as? String
        if let expectedToken, expectedToken != inviteToken {
            throw SharedRoomError.invalidInvite
        }
        let inviteStatus = SharedRoomInviteStatus(
            rawValue: (inviteRecord["status"] as? String) ?? SharedRoomInviteStatus.pending.rawValue
        ) ?? .pending
        let isSingleUse = (inviteRecord["singleUse"] as? Bool) ?? true
        if isSingleUse && inviteStatus == .accepted {
            throw SharedRoomError.inviteAlreadyUsed
        }
        if let revoked = inviteRecord["isRevoked"] as? Int64, revoked != 0 {
            throw SharedRoomError.inviteRevoked
        }
        if let revoked = inviteRecord["isRevoked"] as? Bool, revoked {
            throw SharedRoomError.inviteRevoked
        }
        if let expiresAt = inviteRecord["expiresAt"] as? Date, expiresAt < Date() {
            throw SharedRoomError.inviteExpired
        }

        let roomRecord = try await fetchRecord(recordName: roomRecordName(roomId: roomId))
        let identity = currentUserIdentity()
        let topic = (roomRecord["topic"] as? String) ?? "Shared Room"

        let conversation = existingConversation(roomId: roomId) ?? Conversation(
            topic: topic,
            projectId: projectId,
            threadKind: .group
        )
        if conversation.roomId == nil {
            modelContext?.insert(conversation)
        }

        ensureConversationRoomMetadata(
            conversation,
            role: .guest,
            ownerUserId: roomRecord["ownerUserId"] as? String,
            roomId: roomId
        )
        conversation.topic = topic
        conversation.roomStatus = .syncing
        conversation.roomHistorySyncState = .syncing

        let localUser = ensureLocalUserParticipant(in: conversation, identity: identity)
        localUser.membershipStatus = .active
        try? modelContext?.save()

        inviteRecord["status"] = SharedRoomInviteStatus.accepted.rawValue as CKRecordValue
        inviteRecord["acceptedAt"] = Date() as CKRecordValue
        inviteRecord["updatedAt"] = Date() as CKRecordValue
        _ = try await save(record: inviteRecord)
        _ = upsertLocalInvite(from: inviteRecord)

        try await publishParticipant(localUser, in: conversation)
        await applyDirectTransportHint(for: conversation, hostSequence: conversation.lastRoomHostSequence)
        try await refreshConversation(conversation)
        return conversation
    }

    func declineInvite(_ invite: SharedRoomInvite) async {
        invite.status = .declined
        invite.updatedAt = Date()
        try? modelContext?.save()

        guard isSharedRoomBackendAvailable else {
            unreadInviteCount = pendingInviteCount()
            return
        }

        do {
            let record = try await fetchRecord(recordName: inviteRecordName(inviteId: invite.inviteId))
            record["status"] = SharedRoomInviteStatus.declined.rawValue as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            _ = try await save(record: record)
            _ = upsertLocalInvite(from: record)
            unreadInviteCount = pendingInviteCount()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            unreadInviteCount = pendingInviteCount()
        }
    }

    func publishLocalMessage(_ message: ConversationMessage, in conversation: Conversation) async {
        guard conversation.isSharedRoom else { return }
        guard let senderId = message.senderParticipantId,
              let sender = (conversation.participants ?? []).first(where: { $0.id == senderId }) else { return }
        do {
            ensureParticipantIdentity(sender, in: conversation)
            if message.roomMessageId == nil {
                let roomMessageId = UUID().uuidString
                let sequenceCandidate = max(
                    conversation.lastRoomHostSequence + 1,
                    Int(message.timestamp.timeIntervalSince1970 * 1000)
                )
                conversation.lastRoomHostSequence = sequenceCandidate
                message.roomMessageId = roomMessageId
                message.roomRootMessageId = message.roomRootMessageId ?? roomMessageId
                message.roomOriginNodeId = sender.roomHomeNodeId
                message.roomOriginParticipantId = sender.roomParticipantId
                message.roomHostSequence = sequenceCandidate
                message.roomDeliveryMode = .cloudSync
                try? modelContext?.save()
            }

            let record = CKRecord(
                recordType: Self.messageRecordType,
                recordID: CKRecord.ID(recordName: messageRecordName(roomId: conversation.roomId ?? "", messageId: message.roomMessageId ?? ""))
            )
            record["roomId"] = conversation.roomId as CKRecordValue?
            record["messageId"] = message.roomMessageId as CKRecordValue?
            record["text"] = message.text as CKRecordValue
            record["messageType"] = message.type.rawValue as CKRecordValue
            record["senderParticipantId"] = sender.roomParticipantId as CKRecordValue?
            record["senderDisplayName"] = sender.displayName as CKRecordValue
            record["senderUserId"] = sender.roomUserId as CKRecordValue?
            record["senderNodeId"] = sender.roomHomeNodeId as CKRecordValue?
            record["hostSequence"] = message.roomHostSequence as CKRecordValue
            record["deliveryMode"] = (message.roomDeliveryMode?.rawValue ?? SharedRoomMessageDeliveryMode.cloudSync.rawValue) as CKRecordValue
            record["rootMessageId"] = message.roomRootMessageId as CKRecordValue?
            record["parentMessageId"] = message.roomParentMessageId as CKRecordValue?
            record["originNodeId"] = message.roomOriginNodeId as CKRecordValue?
            record["originParticipantId"] = message.roomOriginParticipantId as CKRecordValue?
            record["createdAt"] = message.timestamp as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            _ = try await save(record: record)
            await applyDirectTransportHint(for: conversation, hostSequence: message.roomHostSequence)
        } catch {
            lastError = error.localizedDescription
            conversation.roomStatus = .unavailable
            try? modelContext?.save()
        }
    }

    func publishLocalParticipants(for conversation: Conversation) async {
        guard conversation.isSharedRoom else { return }
        for participant in (conversation.participants ?? []) where participant.isLocalParticipant {
            do {
                try await publishParticipant(participant, in: conversation)
            } catch {
                lastError = error.localizedDescription
            }
        }
        await applyDirectTransportHint(for: conversation, hostSequence: conversation.lastRoomHostSequence)
    }

    func refreshAll() async {
        guard modelContext != nil else { return }
        guard isSharedRoomBackendAvailable else {
            unreadInviteCount = pendingInviteCount()
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await refreshInviteInbox()
            for conversation in sharedConversations() {
                try await refreshConversation(conversation)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshConversation(_ conversation: Conversation) async throws {
        guard isSharedRoomBackendAvailable else {
            conversation.roomStatus = .unavailable
            conversation.roomHistorySyncState = .failed
            try? modelContext?.save()
            throw SharedRoomError.cloudKitUnavailable
        }
        guard conversation.isSharedRoom, let roomId = conversation.roomId else { return }

        let roomRecords = try await queryRecords(
            recordType: Self.roomRecordType,
            predicate: NSPredicate(format: "roomId == %@", roomId),
            sortDescriptors: [NSSortDescriptor(key: "updatedAt", ascending: false)]
        )
        if let roomRecord = roomRecords.first {
            conversation.topic = (roomRecord["topic"] as? String) ?? conversation.topic
            conversation.roomOwnerUserId = roomRecord["ownerUserId"] as? String
            conversation.roomMembershipVersion = (roomRecord["membershipVersion"] as? Int) ?? ((roomRecord["membershipVersion"] as? Int64).map(Int.init) ?? conversation.roomMembershipVersion)
        }

        let membershipRecords = try await queryRecords(
            recordType: Self.membershipRecordType,
            predicate: NSPredicate(format: "roomId == %@", roomId),
            sortDescriptors: [NSSortDescriptor(key: "joinedAt", ascending: true)]
        )
        for record in membershipRecords {
            applyMembershipRecord(record, to: conversation)
        }

        let messageRecords = try await queryRecords(
            recordType: Self.messageRecordType,
            predicate: NSPredicate(format: "roomId == %@", roomId),
            sortDescriptors: [NSSortDescriptor(key: "hostSequence", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        )
        for record in messageRecords {
            applyMessageRecord(record, to: conversation)
        }

        conversation.roomHistorySyncState = .synced
        conversation.roomStatus = .live
        conversation.lastCloudKitSyncToken = ISO8601DateFormatter().string(from: Date())
        try? modelContext?.save()
    }

    private func startBackgroundSync() {
        syncTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshAll()
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    private func refreshInviteInbox() async throws {
        let identity = currentUserIdentity()
        let records = try await queryRecords(
            recordType: Self.inviteRecordType,
            predicate: NSPredicate(
                format: "recipientLabel == %@ OR recipientLabel == nil",
                identity.displayName
            ),
            sortDescriptors: [NSSortDescriptor(key: "updatedAt", ascending: false)]
        )
        for record in records {
            _ = upsertLocalInvite(from: record)
        }
        markExpiredInvites()
        unreadInviteCount = pendingInviteCount()
    }

    private func ensureConversationRoomMetadata(
        _ conversation: Conversation,
        role: SharedRoomRole,
        ownerUserId: String?,
        roomId: String? = nil
    ) {
        if let roomId, !roomId.isEmpty {
            conversation.roomId = roomId
        } else if conversation.roomId == nil {
            conversation.roomId = UUID().uuidString
        }
        conversation.roomRole = role
        conversation.roomOwnerUserId = ownerUserId
        conversation.roomStatus = .syncing
        conversation.roomHistorySyncState = .idle
        conversation.roomTransportMode = .cloudSync
        conversation.threadKind = .group
    }

    private func ensureLocalUserParticipant(in conversation: Conversation, identity: UserIdentity) -> Participant {
        if let existing = (conversation.participants ?? []).first(where: { $0.typeKind == "user" && $0.isLocalParticipant }) {
            ensureParticipantIdentity(existing, in: conversation, identity: identity)
            return existing
        }

        let participant = Participant(type: .user, displayName: identity.displayName)
        participant.conversation = conversation
        conversation.participants = (conversation.participants ?? []) + [participant]
        modelContext?.insert(participant)
        ensureParticipantIdentity(participant, in: conversation, identity: identity)
        return participant
    }

    private func ensureParticipantIdentity(
        _ participant: Participant,
        in conversation: Conversation,
        identity: UserIdentity? = nil
    ) {
        let resolvedIdentity = identity ?? currentUserIdentity()
        if participant.roomParticipantId == nil || participant.roomParticipantId?.isEmpty == true {
            participant.roomParticipantId = UUID().uuidString
        }
        if participant.roomHomeNodeId == nil || participant.roomHomeNodeId?.isEmpty == true {
            participant.roomHomeNodeId = resolvedIdentity.nodeId
        }

        switch participant.type {
        case .user:
            participant.roomUserId = resolvedIdentity.userId
            participant.displayName = resolvedIdentity.displayName
            participant.isLocalParticipant = true
        case .agentSession(let sessionId):
            participant.roomUserId = resolvedIdentity.userId
            participant.isLocalParticipant = true
            if let session = fetchSession(id: sessionId),
               let agent = session.agent {
                participant.displayName = agent.name
            }
        case .remoteUser, .remoteAgent:
            break
        }

        if conversation.roomMembershipVersion == 0 {
            conversation.roomMembershipVersion = 1
        }
    }

    private func publishParticipant(_ participant: Participant, in conversation: Conversation) async throws {
        ensureParticipantIdentity(participant, in: conversation)
        let record = CKRecord(
            recordType: Self.membershipRecordType,
            recordID: CKRecord.ID(recordName: membershipRecordName(roomId: conversation.roomId ?? "", participantId: participant.roomParticipantId ?? ""))
        )
        record["roomId"] = conversation.roomId as CKRecordValue?
        record["participantId"] = participant.roomParticipantId as CKRecordValue?
        record["displayName"] = participant.displayName as CKRecordValue
        record["membershipStatus"] = participant.membershipStatus.rawValue as CKRecordValue
        record["userId"] = participant.roomUserId as CKRecordValue?
        record["homeNodeId"] = participant.roomHomeNodeId as CKRecordValue?
        record["isLocal"] = participant.isLocalParticipant as CKRecordValue
        record["joinedAt"] = Date() as CKRecordValue

        switch participant.type {
        case .user:
            record["participantType"] = "user" as CKRecordValue
        case .agentSession(let sessionId):
            record["participantType"] = "agent" as CKRecordValue
            record["sessionId"] = sessionId.uuidString as CKRecordValue
            if let session = fetchSession(id: sessionId),
               let agent = session.agent {
                record["agentName"] = agent.name as CKRecordValue
            }
        case .remoteUser(let userId, let participantId, let homeNodeId):
            record["participantType"] = "user" as CKRecordValue
            record["participantId"] = participantId as CKRecordValue
            record["userId"] = userId as CKRecordValue
            record["homeNodeId"] = homeNodeId as CKRecordValue
        case .remoteAgent(let participantId, let homeNodeId, let ownerUserId, let agentName):
            record["participantType"] = "agent" as CKRecordValue
            record["participantId"] = participantId as CKRecordValue
            record["userId"] = ownerUserId as CKRecordValue
            record["homeNodeId"] = homeNodeId as CKRecordValue
            record["agentName"] = agentName as CKRecordValue
        }

        _ = try await save(record: record)
    }

    private func applyMembershipRecord(_ record: CKRecord, to conversation: Conversation) {
        guard let participantId = record["participantId"] as? String else { return }

        let existing = (conversation.participants ?? []).first { $0.roomParticipantId == participantId }
        let participant = existing ?? Participant(type: .remoteUser(userId: "", participantId: participantId, homeNodeId: ""), displayName: "Guest")
        if existing == nil {
            participant.conversation = conversation
            modelContext?.insert(participant)
            conversation.participants = (conversation.participants ?? []) + [participant]
        }

        let displayName = (record["displayName"] as? String) ?? participant.displayName
        let userId = (record["userId"] as? String) ?? participant.roomUserId ?? ""
        let homeNodeId = (record["homeNodeId"] as? String) ?? participant.roomHomeNodeId ?? ""
        let participantType = (record["participantType"] as? String) ?? "user"
        let agentName = (record["agentName"] as? String) ?? displayName
        let localIdentity = currentUserIdentity()
        let isCurrentNodeParticipant = userId == localIdentity.userId && homeNodeId == localIdentity.nodeId

        participant.displayName = displayName
        participant.roomParticipantId = participantId
        participant.roomUserId = userId
        participant.roomHomeNodeId = homeNodeId
        participant.membershipStatus = SharedRoomMembershipStatus(
            rawValue: (record["membershipStatus"] as? String) ?? SharedRoomMembershipStatus.active.rawValue
        ) ?? .active

        if participantType == "agent" {
            let localSessionId = (record["sessionId"] as? String).flatMap(UUID.init(uuidString:))
            if isCurrentNodeParticipant,
               let localSessionId,
               let session = fetchSession(id: localSessionId) {
                participant.type = .agentSession(sessionId: session.id)
                participant.displayName = session.agent?.name ?? agentName
                participant.isLocalParticipant = true
                return
            }

            participant.type = .remoteAgent(
                participantId: participantId,
                homeNodeId: homeNodeId,
                ownerUserId: userId,
                agentName: agentName
            )
            participant.isLocalParticipant = false
        } else {
            if isCurrentNodeParticipant {
                participant.type = .user
                participant.displayName = localIdentity.displayName
                participant.isLocalParticipant = true
            } else {
                participant.type = .remoteUser(
                    userId: userId,
                    participantId: participantId,
                    homeNodeId: homeNodeId
                )
                participant.isLocalParticipant = false
            }
        }
    }

    private func applyMessageRecord(_ record: CKRecord, to conversation: Conversation) {
        guard let roomMessageId = record["messageId"] as? String else { return }
        if (conversation.messages ?? []).contains(where: { $0.roomMessageId == roomMessageId }) {
            return
        }

        let text = (record["text"] as? String) ?? ""
        let senderParticipantId = record["senderParticipantId"] as? String
        let sender = senderParticipantId.flatMap { id in
            (conversation.participants ?? []).first { $0.roomParticipantId == id }
        }
        let typeRaw = (record["messageType"] as? String) ?? MessageType.chat.rawValue
        let messageType = MessageType(rawValue: typeRaw) ?? .chat

        let message = ConversationMessage(
            senderParticipantId: sender?.id,
            text: text,
            type: messageType,
            conversation: conversation
        )
        message.roomMessageId = roomMessageId
        message.roomRootMessageId = record["rootMessageId"] as? String
        message.roomParentMessageId = record["parentMessageId"] as? String
        message.roomOriginNodeId = record["originNodeId"] as? String
        message.roomOriginParticipantId = record["originParticipantId"] as? String
        message.roomHostSequence = (record["hostSequence"] as? Int) ?? ((record["hostSequence"] as? Int64).map(Int.init) ?? 0)
        message.roomDeliveryMode = SharedRoomMessageDeliveryMode(
            rawValue: (record["deliveryMode"] as? String) ?? SharedRoomMessageDeliveryMode.cloudSync.rawValue
        )
        if let createdAt = record["createdAt"] as? Date {
            message.timestamp = createdAt
        }

        conversation.messages = (conversation.messages ?? []) + [message]
        modelContext?.insert(message)
    }

    private func upsertLocalInvite(from record: CKRecord) -> SharedRoomInvite {
        let inviteId = (record["inviteId"] as? String) ?? record.recordID.recordName
        let existing = fetchInvite(inviteId: inviteId)
        let invite = existing ?? SharedRoomInvite(
            inviteId: inviteId,
            inviteToken: record["inviteToken"] as? String,
            roomId: (record["roomId"] as? String) ?? "",
            inviterUserId: (record["inviterUserId"] as? String) ?? "",
            inviterDisplayName: (record["inviterDisplayName"] as? String) ?? "Unknown",
            recipientLabel: record["recipientLabel"] as? String,
            roomTopic: (record["roomTopic"] as? String) ?? "Shared Room",
            deepLink: (record["deepLink"] as? String) ?? "",
            expiresAt: (record["expiresAt"] as? Date) ?? Date(),
            singleUse: (record["singleUse"] as? Bool) ?? true
        )
        invite.inviteToken = (record["inviteToken"] as? String) ?? invite.inviteToken
        invite.roomId = (record["roomId"] as? String) ?? invite.roomId
        invite.inviterUserId = (record["inviterUserId"] as? String) ?? invite.inviterUserId
        invite.inviterDisplayName = (record["inviterDisplayName"] as? String) ?? invite.inviterDisplayName
        invite.recipientLabel = record["recipientLabel"] as? String
        invite.roomTopic = (record["roomTopic"] as? String) ?? invite.roomTopic
        invite.deepLink = (record["deepLink"] as? String) ?? invite.deepLink
        invite.expiresAt = (record["expiresAt"] as? Date) ?? invite.expiresAt
        invite.singleUse = (record["singleUse"] as? Bool) ?? invite.singleUse
        invite.isRevoked = (record["isRevoked"] as? Bool) ?? ((record["isRevoked"] as? Int64) == 1)
        invite.acceptedAt = record["acceptedAt"] as? Date
        invite.updatedAt = (record["updatedAt"] as? Date) ?? Date()
        invite.status = SharedRoomInviteStatus(
            rawValue: (record["status"] as? String) ?? SharedRoomInviteStatus.pending.rawValue
        ) ?? .pending
        if existing == nil {
            modelContext?.insert(invite)
        }
        try? modelContext?.save()
        return invite
    }

    func createLocalTestRoom(topic: String, projectId: UUID? = nil) async throws -> Conversation {
        let conversation = Conversation(topic: topic, projectId: projectId, threadKind: .group)
        modelContext?.insert(conversation)
        try? modelContext?.save()
        try await createSharedRoom(for: conversation)
        return conversation
    }

    func roomConversation(roomId: String) -> Conversation? {
        existingConversation(roomId: roomId)
    }

    func refreshRoom(roomId: String) async throws {
        guard let conversation = existingConversation(roomId: roomId) else {
            throw SharedRoomError.recordNotFound(roomId)
        }
        try await refreshConversation(conversation)
    }

    func sendLocalUserMessage(text: String, roomId: String) async throws -> ConversationMessage {
        guard let conversation = existingConversation(roomId: roomId) else {
            throw SharedRoomError.recordNotFound(roomId)
        }

        let localUser = ensureLocalUserParticipant(in: conversation, identity: currentUserIdentity())
        let message = ConversationMessage(
            senderParticipantId: localUser.id,
            text: text,
            type: .chat,
            conversation: conversation
        )
        conversation.messages = (conversation.messages ?? []) + [message]
        modelContext?.insert(message)
        try? modelContext?.save()
        await publishLocalMessage(message, in: conversation)
        return message
    }

    func roomSnapshot(roomId: String) -> SharedRoomTestAPIService.RoomSnapshot? {
        guard let conversation = existingConversation(roomId: roomId) else { return nil }

        let participants = (conversation.participants ?? [])
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { participant in
                SharedRoomTestAPIService.RoomSnapshot.ParticipantSnapshot(
                    displayName: participant.displayName,
                    type: participant.typeKind,
                    isLocal: participant.isLocalParticipant,
                    membershipStatus: participant.membershipStatus.rawValue,
                    participantId: participant.roomParticipantId,
                    userId: participant.roomUserId,
                    homeNodeId: participant.roomHomeNodeId
                )
            }

        let messages = (conversation.messages ?? [])
            .sorted {
                if $0.roomHostSequence == $1.roomHostSequence {
                    return $0.timestamp < $1.timestamp
                }
                return $0.roomHostSequence < $1.roomHostSequence
            }
            .map { message in
                let sender = message.senderParticipantId.flatMap { senderId in
                    (conversation.participants ?? []).first(where: { $0.id == senderId })
                }
                return SharedRoomTestAPIService.RoomSnapshot.MessageSnapshot(
                    text: message.text,
                    type: message.type.rawValue,
                    senderDisplayName: sender?.displayName,
                    roomMessageId: message.roomMessageId,
                    hostSequence: message.roomHostSequence,
                    deliveryMode: message.roomDeliveryMode?.rawValue,
                    timestamp: message.timestamp
                )
            }

        return SharedRoomTestAPIService.RoomSnapshot(
            roomId: roomId,
            topic: conversation.topic ?? "Shared Room",
            status: conversation.roomStatus.rawValue,
            transportMode: conversation.roomTransportMode.rawValue,
            historySyncState: conversation.roomHistorySyncState.rawValue,
            participants: participants,
            messages: messages
        )
    }

    private func applyDirectTransportHint(for conversation: Conversation, hostSequence: Int) async {
        guard conversation.isSharedRoom, let roomId = conversation.roomId else { return }
        let notifiedPeerCount = await p2pNetworkManager?.broadcastRoomSyncHint(roomId: roomId, hostSequence: hostSequence) ?? 0
        if notifiedPeerCount > 0 {
            conversation.roomTransportMode = .direct
            if conversation.roomStatus != .unavailable {
                conversation.roomStatus = .live
            }
            try? modelContext?.save()
        } else if conversation.roomTransportMode == .direct {
            conversation.roomTransportMode = .cloudSync
            try? modelContext?.save()
        }
    }

    private func existingConversation(roomId: String) -> Conversation? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.roomId == roomId })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchSession(id: UUID) -> Session? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchInvite(inviteId: String) -> SharedRoomInvite? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<SharedRoomInvite>(predicate: #Predicate { $0.inviteId == inviteId })
        return try? modelContext.fetch(descriptor).first
    }

    private func sharedConversations() -> [Conversation] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<Conversation>()
        return ((try? modelContext.fetch(descriptor)) ?? []).filter(\.isSharedRoom)
    }

    private func pendingInviteCount() -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<SharedRoomInvite>()
        return ((try? modelContext.fetch(descriptor)) ?? []).filter {
            $0.status == .pending && !$0.isRevoked && $0.expiresAt > Date()
        }.count
    }

    private func markExpiredInvites() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<SharedRoomInvite>()
        let invites = (try? modelContext.fetch(descriptor)) ?? []
        let now = Date()
        var didChange = false
        for invite in invites where invite.status == .pending && invite.expiresAt <= now {
            invite.status = .expired
            invite.updatedAt = now
            didChange = true
        }
        if didChange {
            try? modelContext.save()
        }
    }

    private func roomRecordName(roomId: String) -> String { "room-\(roomId)" }
    private func inviteRecordName(inviteId: String) -> String { "invite-\(inviteId)" }
    private func membershipRecordName(roomId: String, participantId: String) -> String { "membership-\(roomId)-\(participantId)" }
    private func messageRecordName(roomId: String, messageId: String) -> String { "message-\(roomId)-\(messageId)" }

    private var isCloudKitAvailable: Bool {
        cloudKitContainerIdentifier != nil
    }

    private var isSharedRoomBackendAvailable: Bool {
        localRecordStore != nil || isCloudKitAvailable
    }

    private static func resolveCloudKitContainerIdentifier() -> String? {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return nil
        }

        guard hasValidApplicationIdentifierEntitlement else {
            return nil
        }

        let containers = entitlementStringArray("com.apple.developer.icloud-container-identifiers")
        return containers?.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static var hasValidApplicationIdentifierEntitlement: Bool {
        guard let applicationIdentifier = entitlementString("com.apple.application-identifier") else {
            return false
        }

        let components = applicationIdentifier.split(separator: ".", maxSplits: 1)
        guard components.count == 2 else { return false }
        return components[0].count == 10
    }

    private static func entitlementString(_ key: String) -> String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
        else {
            return nil
        }

        return value as? String
    }

    private static func entitlementStringArray(_ key: String) -> [String]? {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
        else {
            return nil
        }

        if let strings = value as? [String] {
            return strings
        }
        if let strings = value as? NSArray {
            return strings.compactMap { $0 as? String }
        }
        return nil
    }

    private static func makeLocalRecordStore() -> SharedRoomLocalRecordStore? {
        let environment = ProcessInfo.processInfo.environment
        let backend = environment["ODYSSEY_SHARED_ROOM_BACKEND"] ?? environment["CLAUDESTUDIO_SHARED_ROOM_BACKEND"]
        guard backend == "local-test" else {
            return nil
        }

        let storeURL: URL
        if let explicitPath = environment["ODYSSEY_SHARED_ROOM_STORE_PATH"] ?? environment["CLAUDESTUDIO_SHARED_ROOM_STORE_PATH"],
           !explicitPath.isEmpty {
            storeURL = URL(fileURLWithPath: explicitPath)
        } else {
            storeURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".odyssey/shared-room-test/store.plist")
        }
        return SharedRoomLocalRecordStore(storeURL: storeURL)
    }

    private func save(record: CKRecord) async throws -> CKRecord {
        if let localRecordStore {
            return try localRecordStore.save(record: record)
        }
        guard let cloudDatabase else {
            throw SharedRoomError.cloudKitUnavailable
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            cloudDatabase.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let saved {
                    continuation.resume(returning: saved)
                } else {
                    continuation.resume(throwing: SharedRoomError.cloudKitUnavailable)
                }
            }
        }
    }

    private func fetchRecord(recordName: String) async throws -> CKRecord {
        if let localRecordStore {
            return try localRecordStore.fetchRecord(recordName: recordName)
        }
        guard let cloudDatabase else {
            throw SharedRoomError.cloudKitUnavailable
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            cloudDatabase.fetch(withRecordID: CKRecord.ID(recordName: recordName)) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: SharedRoomError.recordNotFound(recordName))
                }
            }
        }
    }

    private func queryRecords(
        recordType: String,
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor] = []
    ) async throws -> [CKRecord] {
        if let localRecordStore {
            return try localRecordStore.queryRecords(
                recordType: recordType,
                predicate: predicate,
                sortDescriptors: sortDescriptors
            )
        }
        guard let cloudDatabase else {
            throw SharedRoomError.cloudKitUnavailable
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord], Error>) in
            let query = CKQuery(recordType: recordType, predicate: predicate)
            query.sortDescriptors = sortDescriptors
            let operation = CKQueryOperation(query: query)
            operation.desiredKeys = nil
            operation.resultsLimit = 200

            var records: [CKRecord] = []
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    records.append(record)
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: records)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            cloudDatabase.add(operation)
        }
    }

    // MARK: - Phase 6 Transport Integration

    func applyRemoteTransportMessage(
        _ msg: InboundTransportMessage,
        to conversation: Conversation,
        context: ModelContext
    ) async {
        // Deduplicate by roomMessageId
        let existing = (conversation.messages ?? []).first(where: { $0.roomMessageId == msg.messageId })
        guard existing == nil else { return }

        let newMessage = ConversationMessage(
            text: msg.text,
            type: .chat,
            conversation: conversation
        )
        newMessage.roomMessageId = msg.messageId
        newMessage.roomDeliveryMode = .matrix
        conversation.messages = (conversation.messages ?? []) + [newMessage]
        try? context.save()
    }
}

enum SharedRoomError: LocalizedError {
    case invalidInvite
    case inviteExpired
    case inviteRevoked
    case inviteAlreadyUsed
    case recordNotFound(String)
    case cloudKitUnavailable
    case localTestBackendUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidInvite:
            return "The invite link is invalid."
        case .inviteExpired:
            return "This invite has expired."
        case .inviteRevoked:
            return "This invite is no longer active."
        case .inviteAlreadyUsed:
            return "This invite has already been used."
        case .recordNotFound(let name):
            return "Missing shared-room record: \(name)"
        case .cloudKitUnavailable:
            return "CloudKit is unavailable right now."
        case .localTestBackendUnavailable:
            return "Local shared-room test backend is unavailable."
        }
    }
}
