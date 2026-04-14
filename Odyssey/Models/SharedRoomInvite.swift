import Foundation
import SwiftData

enum SharedRoomRole: String, Codable, Sendable {
    case host
    case guest
}

enum SharedRoomStatus: String, Codable, Sendable {
    case localOnly
    case syncing
    case live
    case unavailable
}

enum SharedRoomHistorySyncState: String, Codable, Sendable {
    case idle
    case syncing
    case synced
    case failed
}

enum SharedRoomTransportMode: String, Codable, Sendable {
    case direct
    case cloudSync
}

enum SharedRoomMembershipStatus: String, Codable, Sendable {
    case pending
    case active
    case left
    case revoked
}

enum SharedRoomInviteStatus: String, Codable, Sendable {
    case pending
    case accepted
    case declined
    case expired
    case revoked
}

enum SharedRoomMessageDeliveryMode: String, Codable, Sendable {
    case local
    case direct
    case cloudSync
}

@Model
final class SharedRoomInvite {
    var id: UUID
    var inviteId: String
    var inviteToken: String?
    var roomId: String
    var inviterUserId: String
    var inviterDisplayName: String
    var recipientLabel: String?
    var roomTopic: String
    var deepLink: String
    var expiresAt: Date
    var singleUse: Bool
    var isRevoked: Bool
    /// Base64url-encoded `InvitePayload` JSON for device/user pairing invites.
    /// Nil for legacy room invites.
    var signedPayloadJSON: String? = nil
    /// Discriminates between invite kinds: "room" (default), "device", or "user".
    var pairingType: String = "room"
    var acceptedAt: Date?
    // Phase 6 — Matrix federation
    var matrixRoomId: String? = nil
    var matrixHomeserver: String? = nil
    var peerMatrixUserId: String? = nil
    var createdAt: Date
    var updatedAt: Date
    private var statusRaw: String

    var status: SharedRoomInviteStatus {
        get { SharedRoomInviteStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        inviteId: String,
        inviteToken: String?,
        roomId: String,
        inviterUserId: String,
        inviterDisplayName: String,
        recipientLabel: String?,
        roomTopic: String,
        deepLink: String,
        expiresAt: Date,
        singleUse: Bool
    ) {
        let now = Date()
        self.id = UUID()
        self.inviteId = inviteId
        self.inviteToken = inviteToken
        self.roomId = roomId
        self.inviterUserId = inviterUserId
        self.inviterDisplayName = inviterDisplayName
        self.recipientLabel = recipientLabel
        self.roomTopic = roomTopic
        self.deepLink = deepLink
        self.expiresAt = expiresAt
        self.singleUse = singleUse
        self.isRevoked = false
        self.acceptedAt = nil
        self.createdAt = now
        self.updatedAt = now
        self.statusRaw = SharedRoomInviteStatus.pending.rawValue
    }
}
