import Foundation
import OSLog

// MARK: - NostrEventRelay

/// Bridges iOS↔Mac communication over Nostr relay.
///
/// - Receives Nostr events from iOS devices, decrypts (NIP-44), wraps as
///   `nostr.injectCommand`, and injects into the sidecar via raw WebSocket.
/// - Intercepts raw sidecar messages and forwards them to the originating iOS
///   device (NIP-44 encrypted) when the session was initiated via Nostr.
/// - Announces this Mac's Nostr identity to the sidecar on connect.
@MainActor
final class NostrEventRelay {

    private let sidecarManager: SidecarManager
    private var relayManager: NostrRelayManager?
    private var privkeyHex: String?
    private var pubkeyHex: String?

    // Sessions initiated via Nostr: sessionId → iOS sender pubkeyHex
    private var nostrSessions: [String: String] = [:]

    init(sidecarManager: SidecarManager) {
        self.sidecarManager = sidecarManager
    }

    // MARK: - Start / Stop

    func start(privkeyHex: String, pubkeyHex: String, relays: [String]) {
        self.privkeyHex = privkeyHex
        self.pubkeyHex = pubkeyHex

        let manager = NostrRelayManager(
            relayURLs: relays,
            privkeyHex: privkeyHex,
            pubkeyHex: pubkeyHex,
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleIncomingNostrEvent(event)
                }
            }
        )
        relayManager = manager
        manager.connect()

        // Intercept raw sidecar messages and forward to iOS via Nostr
        sidecarManager.rawMessageInterceptor = { [weak self] rawJSON in
            self?.interceptSidecarMessage(rawJSON)
        }

        Task {
            try? await sidecarManager.send(.nostrPeerAnnounce(pubkeyHex: pubkeyHex, relays: relays))
        }
    }

    func stop() {
        relayManager?.disconnect()
        relayManager = nil
        sidecarManager.rawMessageInterceptor = nil
    }

    // MARK: - Outbound: sidecar raw JSON → iOS device via Nostr

    private func interceptSidecarMessage(_ rawJSON: String) {
        guard let data = rawJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = (json["sessionId"] as? String) ?? (json["conversationId"] as? String),
              let iOSPubkey = nostrSessions[sessionId],
              let relay = relayManager,
              let priv = privkeyHex,
              let pub = pubkeyHex else { return }

        Task {
            do {
                let convKey = try NIP44.conversationKey(privkeyHex: priv, peerPubkeyHex: iOSPubkey)
                let encrypted = try NIP44.encrypt(plaintext: rawJSON, conversationKey: convKey)
                let nostrEventJSON = makeEventJSON(content: encrypted, recipientPubkey: iOSPubkey, senderPubkey: pub)
                relay.publish(to: iOSPubkey, eventJSON: nostrEventJSON)
            } catch {
                Log.sidecar.error("NostrEventRelay: outbound publish failed — \(error)")
            }
        }
    }

    // MARK: - Inbound: iOS Nostr event → sidecar via nostr.injectCommand

    private func handleIncomingNostrEvent(_ event: NostrEvent) {
        guard event.kind == 4, let priv = privkeyHex, let pub = pubkeyHex else { return }
        let pTags = event.tags.filter { $0.first == "p" }
        guard pTags.contains(where: { $0.count > 1 && $0[1] == pub }) else { return }

        do {
            let convKey = try NIP44.conversationKey(privkeyHex: priv, peerPubkeyHex: event.pubkey)
            let plaintext = try NIP44.decrypt(payload: event.content, conversationKey: convKey)

            // Track which sessions came from iOS for reply routing
            if let cmdData = plaintext.data(using: .utf8),
               let cmdJSON = try? JSONSerialization.jsonObject(with: cmdData) as? [String: Any] {
                let cmdType = cmdJSON["type"] as? String
                if cmdType == "session.create", let cid = cmdJSON["conversationId"] as? String {
                    nostrSessions[cid] = event.pubkey
                } else if cmdType == "session.message", let sid = cmdJSON["sessionId"] as? String {
                    nostrSessions[sid] = event.pubkey
                }
            }

            // Wrap in nostr.injectCommand and forward to sidecar
            guard let innerData = plaintext.data(using: .utf8),
                  let innerObj = try? JSONSerialization.jsonObject(with: innerData) else { return }
            let wrapper: [String: Any] = ["type": "nostr.injectCommand", "command": innerObj]
            let wrapperData = try JSONSerialization.data(withJSONObject: wrapper)
            guard let wrapperText = String(data: wrapperData, encoding: .utf8) else { return }

            Task {
                try? await self.sidecarManager.sendRaw(wrapperText)
            }
        } catch {
            Log.sidecar.debug("NostrEventRelay: decrypt failed from \(event.pubkey.prefix(8)) — \(error)")
        }
    }

    // MARK: - Helpers

    private func makeEventJSON(content: String, recipientPubkey: String, senderPubkey: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let contentEsc = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"kind":4,"created_at":\(timestamp),"tags":[["p","\(recipientPubkey)"]],"content":"\(contentEsc)","pubkey":"\(senderPubkey)","id":"","sig":""}
        """
    }
}
