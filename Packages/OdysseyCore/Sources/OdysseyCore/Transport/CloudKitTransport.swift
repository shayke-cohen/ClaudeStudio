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
    // TransportManager calls SharedRoomService directly for CloudKit rooms.
    public func connect(credentials: TransportCredentials) async throws {
        // no-op: CloudKit connection is managed by SharedRoomService
    }
    public func disconnect() async {
        // no-op: CloudKit connection is managed by SharedRoomService
        continuation.finish()
    }
    public func send(_ message: OutboundTransportMessage, to room: TransportRoomID) async throws {
        // no-op: messages are published by SharedRoomService directly
    }
    public func createRoom(participants: [RemoteIdentity], name: String?) async throws -> TransportRoomID {
        // CloudKit rooms are created through SharedRoomService, not via this transport.
        throw TransportError.delegatedToService("createRoom is handled by SharedRoomService")
    }
    public func invite(_ identity: RemoteIdentity, to room: TransportRoomID) async throws {
        // no-op: invites are sent via SharedRoomInvite through SharedRoomService
    }
    public func setPresence(_ presence: PresenceStatus) async throws {
        // no-op: CloudKit does not have a presence protocol
    }
    public func searchUsers(query: String) async throws -> [RemoteIdentity] {
        // no-op: CloudKit user search not supported in Phase 6
        return []
    }
}
