// OdysseyiOS/App/iOSAppState.swift
import Foundation
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

    // MARK: - Services

    let sidecarManager = RemoteSidecarManager()
    private let credentialStore = PeerCredentialStore()
    private var eventTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Connect to the first paired Mac and load initial data.
    func connectToFirstPairedMac() async {
        // Use most-recently paired credential so stale creds from previous test sessions don't take priority.
        guard var creds = (try? credentialStore.load())?.sorted(by: { $0.pairedAt > $1.pairedAt }).first else { return }
        // Developer override: if the user typed a host:port in Settings, inject it as the LAN hint
        // so we can recover from stale/missing LAN hints without re-pairing.
        let override = UserDefaults.standard.string(forKey: "macHostOverride") ?? ""
        if !override.trimmingCharacters(in: .whitespaces).isEmpty {
            creds = PeerCredentials(
                id: creds.id,
                displayName: creds.displayName,
                userPublicKeyData: creds.userPublicKeyData,
                tlsCertDER: creds.tlsCertDER,
                wsToken: creds.wsToken,
                wsPort: creds.wsPort,
                lanHint: override.trimmingCharacters(in: .whitespaces),
                wanHint: nil,
                turnRelay: nil,
                turnConfig: nil,
                pairedAt: creds.pairedAt,
                lastConnectedAt: creds.lastConnectedAt,
                claudeSessionIds: creds.claudeSessionIds
            )
        }
        // Cancel any in-flight reconnect loop and force-disconnect so connect() guard passes.
        reconnectTask?.cancel()
        reconnectTask = nil
        sidecarManager.disconnect()
        // Start the event loop before connecting so .connected/.disconnected events
        // are always processed — including on the very first attempt and after failures.
        startEventLoop()
        await sidecarManager.connect(using: creds)
        connectionStatus = sidecarManager.status
        if case .connected = sidecarManager.status {
            await loadConversations()
            await loadProjects()
        }
        // If connect() failed, RemoteSidecarManager yields .disconnected which
        // handleEvent(.disconnected) picks up and starts the reconnect retry task.
    }

    // MARK: - REST loaders

    func loadConversations() async {
        guard let baseURL = currentBaseURL() else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/conversations") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        struct Wrapper: Decodable { let conversations: [ConversationSummaryWire] }
        conversations = (try? JSONDecoder().decode(Wrapper.self, from: data))?.conversations ?? []
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

    /// Start a new session for a conversation, or resume one if a claudeSessionId exists.
    func startOrResumeSession(
        conversationId: String,
        agentId: String,
        model: String = "claude-sonnet-4-6",
        workingDirectory: String?
    ) async throws {
        let peer = sidecarManager.connectedPeer
        let workDir = workingDirectory ?? "~"

        // Check if we have a stored claudeSessionId for this conversation
        if let creds = try? credentialStore.load(),
           let matched = creds.first(where: {
               $0.id == peer?.id && $0.claudeSessionIds[conversationId] != nil
           }),
           let claudeSessionId = matched.claudeSessionIds[conversationId] {
            // Resume existing session
            try await sidecarManager.send(
                .sessionResume(sessionId: conversationId, claudeSessionId: claudeSessionId)
            )
        } else {
            // Create a new session with a minimal AgentConfig
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
            try await sidecarManager.send(
                .sessionCreate(conversationId: conversationId, agentConfig: agentConfig)
            )
        }
        sidecarManager.trackSession(conversationId)
        activeConversationId = conversationId
    }

    /// Send a chat message to the active session.
    func send(_ text: String, to conversationId: String) async throws {
        try await sidecarManager.send(
            .sessionMessage(sessionId: conversationId, text: text, attachments: [], planMode: false)
        )
    }

    /// Pause (interrupt) the active agent session for a conversation.
    func pause(_ conversationId: String) async throws {
        try await sidecarManager.send(.sessionPause(sessionId: conversationId))
    }

    // MARK: - Event loop

    private func startEventLoop() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.sidecarManager.events {
                self.handleEvent(event)
            }
        }
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

    func handleEvent(_ event: SidecarEvent) {
        switch event {
        case .connected:
            reconnectTask?.cancel()
            reconnectTask = nil
            // Restart poll task (was cancelled on disconnect or first connect before startEventLoop)
            if pollTask == nil || pollTask?.isCancelled == true {
                pollTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        guard let self, !Task.isCancelled else { break }
                        await self.loadConversations()
                        await self.loadProjects()
                    }
                }
            }
            Task { [weak self] in
                await self?.loadConversations()
                await self?.loadProjects()
            }
            if let peer = sidecarManager.connectedPeer {
                // Sync from sidecarManager which has the correct method set during WebSocket connection
                connectionStatus = sidecarManager.status
            } else {
                connectionStatus = .connected(method: "lan")
            }
        case .disconnected:
            connectionStatus = .disconnected
            pollTask?.cancel()
            pollTask = nil
            reconnectTask?.cancel()
            reconnectTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard let self, !Task.isCancelled else { break }
                    await self.sidecarManager.reconnectIfNeeded()
                }
            }
        case .streamToken(let sessionId, let token):
            streamingBuffers[sessionId, default: ""] += token
        case .sessionResult(let sessionId, _, _, _, _):
            streamingBuffers.removeValue(forKey: sessionId)
            Task { await loadConversations() }
        default:
            break
        }
    }

    // MARK: - Helpers

    private func currentBaseURL() -> String? {
        guard let peer = sidecarManager.connectedPeer else { return nil }
        let host: String
        if let lan = peer.lanHint {
            host = lan.components(separatedBy: ":").first ?? lan
        } else if let wan = peer.wanHint {
            host = wan.components(separatedBy: ":").first ?? wan
        } else {
            host = "localhost"
        }
        // HTTP API port is WS port + 1; sidecar serves plain HTTP (not HTTPS)
        let httpPort = peer.wsPort + 1
        return "http://\(host):\(httpPort)"
    }
}
