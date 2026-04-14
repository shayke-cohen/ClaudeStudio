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

    // MARK: - Lifecycle

    /// Connect to the first paired Mac and load initial data.
    func connectToFirstPairedMac() async {
        guard let creds = (try? credentialStore.load())?.first else { return }
        await sidecarManager.connect(using: creds)
        connectionStatus = sidecarManager.status
        startEventLoop()
        await loadConversations()
        await loadProjects()
    }

    // MARK: - REST loaders

    func loadConversations() async {
        guard let baseURL = currentBaseURL() else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/conversations") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        conversations = (try? JSONDecoder().decode([ConversationSummaryWire].self, from: data)) ?? []
    }

    func loadMessages(for conversationId: String) async -> [MessageWire] {
        guard let baseURL = currentBaseURL() else { return [] }
        guard let url = URL(
            string: "\(baseURL)/api/v1/conversations/\(conversationId)/messages?limit=50"
        ) else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        return (try? JSONDecoder().decode([MessageWire].self, from: data)) ?? []
    }

    func loadProjects() async {
        guard let baseURL = currentBaseURL() else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/projects") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        projects = (try? JSONDecoder().decode([ProjectSummaryWire].self, from: data)) ?? []
    }

    // MARK: - Session management

    /// Start a new session for a conversation, or resume one if a claudeSessionId exists.
    func startOrResumeSession(
        conversationId: String,
        agentId: String,
        workingDirectory: String?
    ) async throws {
        let peer = sidecarManager.connectedPeer
        let workDir = workingDirectory ?? peer.flatMap { $0.lanHint }.map { _ in "~" } ?? "~"

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
                model: "claude-opus-4-5",
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

    // MARK: - Event loop

    private func startEventLoop() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.sidecarManager.events {
                await MainActor.run { self.handleEvent(event) }
            }
        }
    }

    private func handleEvent(_ event: SidecarEvent) {
        switch event {
        case .connected:
            // Determine method from current peer
            if let peer = sidecarManager.connectedPeer {
                let method: RemoteSidecarManager.ConnectionMethod = peer.lanHint != nil ? .lan : .wanDirect
                connectionStatus = .connected(method: method.rawValue)
            } else {
                connectionStatus = .connected(method: "lan")
            }
        case .disconnected:
            connectionStatus = .disconnected
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
        // HTTP API port is WS port + 1
        let httpPort = peer.wsPort + 1
        return "https://\(host):\(httpPort)"
    }
}
