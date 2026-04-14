// Packages/OdysseyCore/Sources/OdysseyCore/Transport/Transport.swift
import Foundation

// MARK: - Wire types

public typealias TransportRoomID = String

public struct OutboundTransportMessage: Sendable {
    public let messageId: String
    public let roomId: TransportRoomID
    public let senderId: String
    public let senderDisplayName: String
    public let participantType: String   // "user" | "agent"
    public let text: String
    public let timestamp: Date
    public let agentBundleJSON: String?  // Phase 5 AgentIdentityBundle, optional

    public init(
        messageId: String,
        roomId: TransportRoomID,
        senderId: String,
        senderDisplayName: String,
        participantType: String,
        text: String,
        timestamp: Date = Date(),
        agentBundleJSON: String? = nil
    ) {
        self.messageId = messageId
        self.roomId = roomId
        self.senderId = senderId
        self.senderDisplayName = senderDisplayName
        self.participantType = participantType
        self.text = text
        self.timestamp = timestamp
        self.agentBundleJSON = agentBundleJSON
    }
}

public struct InboundTransportMessage: Sendable {
    public let messageId: String
    public let roomId: TransportRoomID
    public let senderId: String
    public let senderDisplayName: String
    public let participantType: String
    public let text: String
    public let timestamp: Date
    public let agentBundleJSON: String?
    public let transportId: String  // identifies which Transport delivered this

    public init(
        messageId: String,
        roomId: TransportRoomID,
        senderId: String,
        senderDisplayName: String,
        participantType: String,
        text: String,
        timestamp: Date,
        agentBundleJSON: String?,
        transportId: String
    ) {
        self.messageId = messageId
        self.roomId = roomId
        self.senderId = senderId
        self.senderDisplayName = senderDisplayName
        self.participantType = participantType
        self.text = text
        self.timestamp = timestamp
        self.agentBundleJSON = agentBundleJSON
        self.transportId = transportId
    }
}

public enum PresenceStatus: String, Sendable {
    case online
    case unavailable
    case offline
}

public struct TransportCredentials: Sendable {
    public let homeserverURL: URL?
    public let accessToken: String?
    public let deviceId: String?
    public let userId: String?

    public static let cloudKit = TransportCredentials(
        homeserverURL: nil, accessToken: nil, deviceId: nil, userId: nil
    )

    public init(homeserverURL: URL?, accessToken: String?, deviceId: String?, userId: String?) {
        self.homeserverURL = homeserverURL
        self.accessToken = accessToken
        self.deviceId = deviceId
        self.userId = userId
    }
}

// MARK: - RemoteIdentity

public struct RemoteIdentity: Codable, Hashable, Sendable {
    public let matrixId: String?           // "@user:homeserver"
    public let publicKeyData: Data?        // Ed25519 from Phase 1
    public let displayName: String
    public let isAgent: Bool
    public let ownerPublicKeyData: Data?   // owner's key when isAgent == true

    public init(
        matrixId: String?,
        publicKeyData: Data?,
        displayName: String,
        isAgent: Bool,
        ownerPublicKeyData: Data? = nil
    ) {
        self.matrixId = matrixId
        self.publicKeyData = publicKeyData
        self.displayName = displayName
        self.isAgent = isAgent
        self.ownerPublicKeyData = ownerPublicKeyData
    }
}

// MARK: - RoomOrigin

public enum RoomOrigin: Codable, Sendable, Equatable {
    case local
    case cloudKit
    case matrix(homeserver: String, roomId: String)

    // Flat storage helpers (mirrors existing roomRoleRaw / roomStatusRaw pattern)
    public var kindString: String {
        switch self {
        case .local:   return "local"
        case .cloudKit: return "cloudKit"
        case .matrix:  return "matrix"
        }
    }

    public var homeserver: String? {
        if case .matrix(let hs, _) = self { return hs }
        return nil
    }

    public var matrixRoomId: String? {
        if case .matrix(_, let rid) = self { return rid }
        return nil
    }

    public static func from(kind: String, homeserver: String?, matrixRoomId: String?) -> RoomOrigin {
        switch kind {
        case "cloudKit": return .cloudKit
        case "matrix":
            if let hs = homeserver, let rid = matrixRoomId {
                return .matrix(homeserver: hs, roomId: rid)
            }
            return .local
        default: return .local
        }
    }
}

// MARK: - TransportDelegate

public protocol TransportDelegate: AnyObject, Sendable {
    func transport(_ transport: any Transport, didReceive message: InboundTransportMessage) async
    func transport(_ transport: any Transport, didChangePresence userId: String, status: PresenceStatus) async
    func transport(_ transport: any Transport, didFailWithError error: Error) async
}

// MARK: - Transport protocol

public protocol Transport: AnyObject, Sendable {
    var id: String { get }
    var displayName: String { get }
    var delegate: (any TransportDelegate)? { get set }

    func connect(credentials: TransportCredentials) async throws
    func disconnect() async
    func send(_ message: OutboundTransportMessage, to room: TransportRoomID) async throws
    func createRoom(participants: [RemoteIdentity], name: String?) async throws -> TransportRoomID
    func invite(_ identity: RemoteIdentity, to room: TransportRoomID) async throws
    func setPresence(_ presence: PresenceStatus) async throws
    func searchUsers(query: String) async throws -> [RemoteIdentity]
    var inbound: AsyncStream<InboundTransportMessage> { get }
}
