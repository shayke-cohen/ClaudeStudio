// Packages/OdysseyCore/Sources/OdysseyCore/Transport/CloudKitTransport.swift
// Thin adapter so TransportManager can treat CloudKit rooms uniformly.
// Heavy lifting stays in SharedRoomService; this adapter forwards calls.
import Foundation

public final class CloudKitTransport: Transport {
    public let id = "cloudkit"
    public let displayName = "CloudKit"
    public weak var delegate: (any TransportDelegate)?

    private let _stream: AsyncStream<InboundTransportMessage>
    private let continuation: AsyncStream<InboundTransportMessage>.Continuation

    public init() {
        (_stream, continuation) = AsyncStream.makeStream()
    }

    public var inbound: AsyncStream<InboundTransportMessage> { _stream }

    /// Called by SharedRoomService when a remote message arrives from CloudKit.
    public func deliverInbound(_ message: InboundTransportMessage) {
        continuation.yield(message)
    }

    // Transport protocol stubs — SharedRoomService owns the real implementation.
    public func connect(credentials: TransportCredentials) async throws {}
    public func disconnect() async { continuation.finish() }
    public func send(_ message: OutboundTransportMessage, to room: TransportRoomID) async throws {}
    public func createRoom(participants: [RemoteIdentity], name: String?) async throws -> TransportRoomID { "" }
    public func invite(_ identity: RemoteIdentity, to room: TransportRoomID) async throws {}
    public func setPresence(_ presence: PresenceStatus) async throws {}
    public func searchUsers(query: String) async throws -> [RemoteIdentity] { [] }
}
