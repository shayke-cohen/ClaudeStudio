// Odyssey/Services/MatrixTransport.swift
import Foundation
import OdysseyCore
import OSLog

private let logger = Logger(subsystem: "com.odyssey.app", category: "MatrixTransport")

final class MatrixTransport: Transport {
    let id = "matrix"
    let displayName = "Matrix"
    // nonisolated(unsafe) because the Transport protocol requires Sendable and delegate is set from main actor
    nonisolated(unsafe) weak var delegate: (any TransportDelegate)?

    private let instanceName: String
    private let keychainStore: MatrixKeychainStore
    // nonisolated(unsafe) — mutated only on the calling actor (main) before sync loop starts
    nonisolated(unsafe) private(set) var client: MatrixClient?
    nonisolated(unsafe) private var syncTask: Task<Void, Never>?
    nonisolated(unsafe) private var syncToken: String?

    private let _stream: AsyncStream<InboundTransportMessage>
    private let inboundContinuation: AsyncStream<InboundTransportMessage>.Continuation

    var inbound: AsyncStream<InboundTransportMessage> { _stream }

    init(instanceName: String) {
        self.instanceName = instanceName
        self.keychainStore = MatrixKeychainStore(instanceName: instanceName)
        (_stream, inboundContinuation) = AsyncStream.makeStream()
    }

    // MARK: - Transport protocol

    func connect(credentials: TransportCredentials) async throws {
        guard let matrixCreds = try keychainStore.loadCredentials() else {
            logger.warning("MatrixTransport: no credentials in Keychain for \(self.instanceName)")
            return
        }
        let homeserver = matrixCreds.homeserver
        let matrixClient = MatrixClient(homeserver: homeserver, credentials: matrixCreds)
        self.client = matrixClient
        syncToken = keychainStore.loadSyncToken()

        try await matrixClient.setPresence(status: "online", statusMsg: nil)
        startSyncLoop()
    }

    func disconnect() async {
        syncTask?.cancel()
        syncTask = nil
        try? await client?.setPresence(status: "offline", statusMsg: nil)
        inboundContinuation.finish()
    }

    func send(_ message: OutboundTransportMessage, to room: TransportRoomID) async throws {
        guard let client else { throw MatrixError.missingField("client not connected") }
        let preview = String(message.text.prefix(200))
        var odysseyPayload: [String: Any] = [
            "messageId": message.messageId,
            "senderId": message.senderId,
            "participantType": message.participantType
        ]
        if let bundle = message.agentBundleJSON { odysseyPayload["agentBundle"] = bundle }
        let content: [String: Any] = [
            "msgtype": "m.text",
            "body": preview,
            "odyssey": odysseyPayload
        ]
        _ = try await client.sendEvent(roomId: room, type: "m.room.message", content: content)
    }

    func createRoom(participants: [RemoteIdentity], name: String?) async throws -> TransportRoomID {
        guard let client else { throw MatrixError.missingField("client not connected") }
        let userIds = participants.compactMap(\.matrixId)
        return try await client.createRoom(name: name, inviteUserIds: userIds)
    }

    func invite(_ identity: RemoteIdentity, to room: TransportRoomID) async throws {
        guard let client, let matrixId = identity.matrixId else { return }
        try await client.inviteUser(matrixId, to: room)
    }

    func setPresence(_ presence: PresenceStatus) async throws {
        try await client?.setPresence(status: presence.rawValue, statusMsg: nil)
    }

    func searchUsers(query: String) async throws -> [RemoteIdentity] {
        guard let client else { return [] }
        let results = try await client.searchUsers(query: query)
        return results.map { user in
            RemoteIdentity(
                matrixId: user.userId,
                publicKeyData: nil,
                displayName: user.displayName ?? user.userId,
                isAgent: false
            )
        }
    }

    // MARK: - Sync loop

    private func startSyncLoop() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            await self?.syncLoop()
        }
    }

    private func syncLoop() async {
        var backoffSeconds: Double = 2
        let maxBackoff: Double = 30
        var refreshAttempted = false

        while !Task.isCancelled {
            guard let client else { break }
            do {
                let response = try await client.sync(since: syncToken, timeout: 30_000)
                backoffSeconds = 2  // reset on success
                refreshAttempted = false
                syncToken = response.nextBatch
                keychainStore.saveSyncToken(response.nextBatch)
                await deliverEvents(from: response)
            } catch MatrixError.unknownToken {
                logger.warning("MatrixTransport: access token expired, attempting refresh")
                guard !refreshAttempted else {
                    logger.error("MatrixTransport: token still invalid after refresh, giving up")
                    await delegate?.transport(self, didFailWithError: MatrixError.unknownToken)
                    break
                }
                refreshAttempted = true
                do {
                    guard let refreshToken = client.credentials?.refreshToken else {
                        logger.error("MatrixTransport: no refresh token available, giving up")
                        await delegate?.transport(self, didFailWithError: MatrixError.unknownToken)
                        break
                    }
                    let newCreds = try await client.refreshToken(refreshToken)
                    client.credentials = newCreds
                    try keychainStore.saveCredentials(newCreds)
                    logger.info("MatrixTransport: token refreshed successfully")
                } catch {
                    logger.error("MatrixTransport: token refresh failed: \(error)")
                    await delegate?.transport(self, didFailWithError: error)
                    break
                }
            } catch {
                if Task.isCancelled { break }
                logger.warning("MatrixTransport: sync error (backoff \(backoffSeconds)s): \(error)")
                await delegate?.transport(self, didFailWithError: error)
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
                backoffSeconds = min(backoffSeconds * 2, maxBackoff)
            }
        }
    }

    private func deliverEvents(from response: MatrixSyncResponse) async {
        for roomEvents in response.rooms {
            for event in roomEvents.events where event.type == "m.room.message" {
                guard let odyssey = event.content["odyssey"] as? [String: Any],
                      let messageId = odyssey["messageId"] as? String,
                      let senderId = odyssey["senderId"] as? String,
                      let participantType = odyssey["participantType"] as? String,
                      let text = event.content["body"] as? String else { continue }

                let msg = InboundTransportMessage(
                    messageId: messageId,
                    roomId: roomEvents.roomId,
                    senderId: senderId,
                    senderDisplayName: event.sender,
                    participantType: participantType,
                    text: text,
                    timestamp: Date(timeIntervalSince1970: Double(event.originServerTs) / 1000),
                    agentBundleJSON: odyssey["agentBundle"] as? String,
                    transportId: id
                )
                inboundContinuation.yield(msg)
            }
        }
    }
}
