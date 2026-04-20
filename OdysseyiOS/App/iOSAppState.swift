// OdysseyiOS/App/iOSAppState.swift
import Foundation
import UIKit
import OdysseyCore

/// Global observable state for the iOS thin-client app.
@MainActor
@Observable
final class iOSAppState {

    // MARK: - Observed state

    var conversations: [ConversationSummaryWire] = []
    var streamingBuffers: [String: String] = [:]
    var activeConversationId: String?
    var projects: [ProjectSummaryWire] = []
    var connectionStatus = RemoteSidecarManager.ConnectionStatus.disconnected
    var lanLoadError: String? = nil

    // MARK: - Services

    private let credentialStore = PeerCredentialStore()
    private(set) var nostrBridge: NostrSidecarBridge?
    private var pollTask: Task<Void, Never>?
    private var storedCredentials: PeerCredentials?

    // MARK: - Lifecycle

    func connectToFirstPairedMac() async {
        guard let creds = (try? credentialStore.load())?.sorted(by: { $0.pairedAt > $1.pairedAt }).first else { return }
        storedCredentials = creds
        connectNostrBridge(using: creds)
    }

    // MARK: - Nostr bridge

    private func connectNostrBridge(using creds: PeerCredentials) {
        nostrBridge?.disconnect()
        nostrBridge = nil
        guard let keypair = iOSNostrKeychain.loadOrGenerateKeypair() else { return }
        connectionStatus = .connecting
        let relays = creds.relayURLs.isEmpty
            ? ["wss://relay.damus.io", "wss://relay.nostr.band"]
            : creds.relayURLs
        let bridge = NostrSidecarBridge(
            macPubkeyHex: creds.macNostrPubkeyHex,
            privkeyHex: keypair.privkeyHex,
            pubkeyHex: keypair.pubkeyHex,
            relayURLs: relays,
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleEvent(event)
                }
            }
        )
        nostrBridge = bridge
        bridge.connect()
        // Nostr relay is always-on once started; treat as connected immediately
        connectionStatus = .connected(method: "nostr")
        startPollTask()
        Task {
            await loadConversations()
            await loadProjects()
        }
        // Announce iOS npub to Mac so it can register this device as trusted.
        // 1-second delay lets the relay WebSocket handshake complete first.
        let iosNpub = keypair.pubkeyHex
        let deviceName = UIDevice.current.name
        Task {
            try? await Task.sleep(for: .seconds(1))
            bridge.send(.pairingHello(iosNpub: iosNpub, displayName: deviceName))
        }
    }

    // MARK: - REST loaders (LAN fast-path when lanHint is available)

    func loadConversations() async {
        // Try LAN fast-path first (5s timeout so isolated networks fall through quickly)
        if let baseURL = currentBaseURL(),
           let url = URL(string: "\(baseURL)/api/v1/conversations") {
            do {
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
                let (data, _) = try await URLSession.shared.data(for: request)
                struct Wrapper: Decodable { let conversations: [ConversationSummaryWire] }
                if let decoded = try? JSONDecoder().decode(Wrapper.self, from: data) {
                    conversations = decoded.conversations
                    lanLoadError = nil
                    return
                }
            } catch {
                // LAN unreachable — fall through to Nostr relay path
            }
        }
        // Nostr relay fallback: request conversations via encrypted relay
        if let bridge = nostrBridge {
            bridge.send(.conversationsList)
        } else {
            lanLoadError = "Not connected (no LAN and no Nostr bridge)"
        }
    }

    func loadMessages(for conversationId: String) async -> [MessageWire] {
        guard let baseURL = currentBaseURL() else { return [] }
        guard let url = URL(
            string: "\(baseURL)/api/v1/conversations/\(conversationId)/messages?limit=50"
        ) else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        struct Wrapper: Decodable { let messages: [MessageWire] }
        return (try? JSONDecoder().decode(Wrapper.self, from: data))?.messages ?? []
    }

    func loadProjects() async {
        guard let baseURL = currentBaseURL() else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/projects") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        struct Wrapper: Decodable { let projects: [ProjectSummaryWire] }
        projects = (try? JSONDecoder().decode(Wrapper.self, from: data))?.projects ?? []
    }

    // MARK: - Session management

    func startOrResumeSession(
        conversationId: String,
        agentId: String,
        model: String = "claude-sonnet-4-6",
        workingDirectory: String?
    ) async throws {
        let workDir = workingDirectory ?? "~"
        if let creds = try? credentialStore.load(),
           let matched = creds.first(where: { $0.claudeSessionIds[conversationId] != nil }),
           let claudeSessionId = matched.claudeSessionIds[conversationId] {
            nostrBridge?.send(.sessionResume(sessionId: conversationId, claudeSessionId: claudeSessionId))
        } else {
            let agentConfig = AgentConfig(
                name: agentId,
                systemPrompt: "",
                allowedTools: [],
                mcpServers: [],
                provider: "claude",
                model: model,
                maxTurns: nil,
                maxBudget: nil,
                maxThinkingTokens: nil,
                workingDirectory: workDir,
                skills: [],
                interactive: true
            )
            nostrBridge?.send(.sessionCreate(conversationId: conversationId, agentConfig: agentConfig))
        }
        activeConversationId = conversationId
    }

    func send(_ text: String, to conversationId: String) async throws {
        nostrBridge?.send(.sessionMessage(sessionId: conversationId, text: text, attachments: [], planMode: false))
    }

    func pause(_ conversationId: String) async throws {
        nostrBridge?.send(.sessionPause(sessionId: conversationId))
    }

    // MARK: - Event handling

    func handleEvent(_ event: SidecarEvent) {
        switch event {
        case .connected:
            connectionStatus = .connected(method: "nostr")
            Task {
                await loadConversations()
                await loadProjects()
            }
        case .disconnected:
            // NostrSidecarBridge reconnects internally; reflect current state
            connectionStatus = .disconnected
        case .streamToken(let sessionId, let token):
            streamingBuffers[sessionId, default: ""] += token
        case .sessionResult(let sessionId, _, _, _, _):
            streamingBuffers.removeValue(forKey: sessionId)
            Task { await loadConversations() }
        case .conversationsListResult(let list):
            conversations = list
            lanLoadError = nil
        default:
            break
        }
    }

    // MARK: - Helpers

    private func startPollTask() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { break }
                await self.loadConversations()
                await self.loadProjects()
            }
        }
    }

    var lanBaseURL: String? { currentBaseURL() }

    private func currentBaseURL() -> String? {
        guard let lan = storedCredentials?.lanHint else { return nil }
        let host = lan.components(separatedBy: ":").first ?? lan
        return "http://\(host):9850"
    }
}
