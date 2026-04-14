// Odyssey/Services/TransportManager.swift
import Foundation
import SwiftData
import OdysseyCore
import OSLog

private let logger = Logger(subsystem: "com.odyssey.app", category: "TransportManager")

@MainActor
final class TransportManager: ObservableObject {
    let cloudKitTransport: CloudKitTransport
    let matrixTransport: MatrixTransport

    private var inboundTask: Task<Void, Never>?

    /// Called when a remote message arrives from any transport.
    var onInboundMessage: ((InboundTransportMessage) async -> Void)?
    /// Called when a presence update arrives.
    var onPresenceChanged: (@MainActor (String, PresenceStatus) async -> Void)?

    init(instanceName: String) {
        self.cloudKitTransport = CloudKitTransport()
        self.matrixTransport = MatrixTransport(instanceName: instanceName)
    }

    // MARK: - Lifecycle

    func start() async {
        do {
            try await matrixTransport.connect(credentials: .cloudKit)
        } catch {
            logger.warning("TransportManager: Matrix connect failed: \(error)")
        }
        startInboundRelay()
    }

    func stop() async {
        inboundTask?.cancel()
        await matrixTransport.disconnect()
    }

    // MARK: - Outbound routing

    func send(_ message: OutboundTransportMessage, for conversation: Conversation) async {
        switch conversation.roomOrigin {
        case .local:
            return
        case .cloudKit:
            // CloudKit messages are published by SharedRoomService directly.
            return
        case .matrix(_, let matrixRoomId):
            do {
                try await matrixTransport.send(message, to: matrixRoomId)
                logger.debug("TransportManager: sent to Matrix room \(matrixRoomId)")
            } catch {
                logger.error("TransportManager: Matrix send failed: \(error)")
            }
        }
    }

    // MARK: - Inbound relay

    private func startInboundRelay() {
        inboundTask?.cancel()
        inboundTask = Task { [weak self] in
            guard let self else { return }
            for await message in self.matrixTransport.inbound {
                await self.onInboundMessage?(message)
            }
        }
    }
}

