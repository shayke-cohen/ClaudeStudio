import SwiftUI
import SwiftData
import Combine

@MainActor
final class AppState: ObservableObject {
    enum SidecarStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    @Published var sidecarStatus: SidecarStatus = .disconnected
    @Published var selectedConversationId: UUID?
    @Published var showAgentLibrary = false
    @Published var showNewSessionSheet = false
    @Published var showPeerNetwork = false
    @Published var showAgentComms = false
    @Published var showDirectoryPicker = false
    @Published private(set) var instanceWorkingDirectory: String?
    @Published var activeSessions: [UUID: SessionInfo] = [:]
    @Published var streamingText: [String: String] = [:]
    @Published var lastSessionEvent: [String: SessionEventKind] = [:]
    @Published private(set) var allocatedWsPort: Int = 0
    @Published private(set) var allocatedHttpPort: Int = 0

    @Published var toolCalls: [String: [ToolCallInfo]] = [:]
    @Published var commsEvents: [CommsEvent] = []
    @Published var fileTreeRefreshTrigger: Int = 0

    var createdSessions: Set<String> = []

    enum SessionEventKind {
        case result
        case error(String)
    }

    struct SessionInfo: Identifiable {
        let id: UUID
        let agentName: String
        var tokenCount: Int = 0
        var cost: Double = 0
        var isStreaming: Bool = false
    }

    struct ToolCallInfo: Identifiable {
        let id = UUID()
        let tool: String
        let input: String
        var output: String?
        let timestamp: Date
    }

    struct CommsEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let kind: CommsEventKind
    }

    enum CommsEventKind {
        case chat(channelId: String, from: String, message: String)
        case delegation(from: String, to: String, task: String)
        case blackboardUpdate(key: String, value: String, writtenBy: String)
    }

    private static let fileModifyingTools: Set<String> = [
        "write", "edit", "multiedit", "multi_edit", "create", "mv", "cp",
        "writefile", "createfile", "renamefile", "deletefile"
    ]

    private(set) var sidecarManager: SidecarManager?
    private var eventTask: Task<Void, Never>?
    var modelContext: ModelContext?

    func loadInstanceWorkingDirectory() {
        instanceWorkingDirectory = InstanceConfig.userDefaults.string(
            forKey: AppSettings.instanceWorkingDirectoryKey
        )
        if instanceWorkingDirectory == nil {
            showDirectoryPicker = true
        }
    }

    func setInstanceWorkingDirectory(_ path: String) {
        instanceWorkingDirectory = path
        InstanceConfig.userDefaults.set(path, forKey: AppSettings.instanceWorkingDirectoryKey)
    }

    func connectSidecar() {
        guard sidecarStatus == .disconnected || {
            if case .error = sidecarStatus { return true }
            return false
        }() else { return }

        sidecarStatus = .connecting

        let defaults = InstanceConfig.userDefaults
        let preferredWsPort = defaults.object(forKey: AppSettings.wsPortKey) as? Int ?? AppSettings.defaultWsPort
        let preferredHttpPort = defaults.object(forKey: AppSettings.httpPortKey) as? Int ?? AppSettings.defaultHttpPort
        let bunOverride = defaults.string(forKey: AppSettings.bunPathOverrideKey)
        let sidecarPathOverride = defaults.string(forKey: AppSettings.sidecarPathKey)

        let wsPort = InstanceConfig.isDefault ? preferredWsPort : InstanceConfig.findFreePort()
        let httpPort = InstanceConfig.isDefault ? preferredHttpPort : InstanceConfig.findFreePort()
        allocatedWsPort = wsPort
        allocatedHttpPort = httpPort

        let config = SidecarManager.Config(
            wsPort: wsPort,
            httpPort: httpPort,
            logDirectory: InstanceConfig.logDirectory.path,
            dataDirectory: InstanceConfig.baseDirectory.path,
            bunPathOverride: bunOverride?.isEmpty == true ? nil : bunOverride,
            sidecarPathOverride: sidecarPathOverride?.isEmpty == true ? nil : sidecarPathOverride
        )
        let manager = SidecarManager(config: config)
        self.sidecarManager = manager
        Task {
            do {
                try await manager.start()
                sidecarStatus = .connected
                listenForEvents(from: manager)
                registerAgentDefinitions()
            } catch {
                sidecarStatus = .error(error.localizedDescription)
            }
        }
    }

    func disconnectSidecar() {
        eventTask?.cancel()
        eventTask = nil
        sidecarManager?.stop()
        sidecarManager = nil
        sidecarStatus = .disconnected
    }

    func sendToSidecar(_ command: SidecarCommand) {
        guard let manager = sidecarManager else { return }
        Task {
            try? await manager.send(command)
        }
    }

    private func registerAgentDefinitions() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<Agent>()
        guard let agents = try? ctx.fetch(descriptor), !agents.isEmpty else { return }

        let provisioner = AgentProvisioner(modelContext: ctx)
        let defs: [AgentDefinitionWire] = agents.compactMap { agent in
            let (config, _) = provisioner.provision(agent: agent, mission: nil)
            let policyStr: String
            switch agent.instancePolicy {
            case .spawn: policyStr = "spawn"
            case .singleton: policyStr = "singleton"
            case .pool: policyStr = "pool"
            }
            return AgentDefinitionWire(name: agent.name, config: config, instancePolicy: policyStr)
        }

        sendToSidecar(.agentRegister(agents: defs))
        print("[AppState] Registered \(defs.count) agent definitions with sidecar")
    }

    private func listenForEvents(from manager: SidecarManager) {
        eventTask = Task {
            for await event in manager.events {
                handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: SidecarEvent) {
        switch event {
        case .streamToken(let sessionId, let text):
            let current = streamingText[sessionId] ?? ""
            streamingText[sessionId] = current + text
            activeSessions[UUID(uuidString: sessionId) ?? UUID()]?.isStreaming = true

        case .streamToolCall(let sessionId, let tool, let input):
            var calls = toolCalls[sessionId] ?? []
            calls.append(ToolCallInfo(tool: tool, input: input, timestamp: Date()))
            toolCalls[sessionId] = calls

        case .streamToolResult(let sessionId, let tool, let output):
            if var calls = toolCalls[sessionId],
               let idx = calls.lastIndex(where: { $0.tool == tool && $0.output == nil }) {
                calls[idx].output = output
                toolCalls[sessionId] = calls
            }
            if Self.fileModifyingTools.contains(tool.lowercased()) {
                fileTreeRefreshTrigger += 1
            }

        case .sessionResult(let sessionId, let resultText, let cost):
            activeSessions[UUID(uuidString: sessionId) ?? UUID()]?.isStreaming = false
            activeSessions[UUID(uuidString: sessionId) ?? UUID()]?.cost += cost
            if streamingText[sessionId]?.isEmpty != false, !resultText.isEmpty {
                streamingText[sessionId] = resultText
            }
            lastSessionEvent[sessionId] = .result

        case .sessionError(let sessionId, let error):
            activeSessions[UUID(uuidString: sessionId) ?? UUID()]?.isStreaming = false
            lastSessionEvent[sessionId] = .error(error)
            print("[AppState] Session \(sessionId) error: \(error)")

        case .peerChat(let channelId, let from, let message):
            commsEvents.append(CommsEvent(
                timestamp: Date(),
                kind: .chat(channelId: channelId, from: from, message: message)
            ))
            persistPeerChatMessage(channelId: channelId, from: from, message: message)

        case .peerDelegate(let from, let to, let task):
            commsEvents.append(CommsEvent(
                timestamp: Date(),
                kind: .delegation(from: from, to: to, task: task)
            ))
            persistDelegationEvent(from: from, to: to, task: task)

        case .blackboardUpdate(let key, let value, let writtenBy):
            commsEvents.append(CommsEvent(
                timestamp: Date(),
                kind: .blackboardUpdate(key: key, value: value, writtenBy: writtenBy)
            ))
            persistBlackboardUpdate(key: key, value: value, writtenBy: writtenBy)

        case .connected:
            sidecarStatus = .connected

        case .disconnected:
            sidecarStatus = .disconnected
        }
    }

    // MARK: - Persistence helpers for inter-agent events

    private func persistPeerChatMessage(channelId: String, from: String, message: String) {
        guard let ctx = modelContext else { return }

        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { conv in
            conv.topic == channelId
        })
        let existing = try? ctx.fetch(descriptor).first

        if let convo = existing {
            let msg = ConversationMessage(text: "[\(from)] \(message)", type: .chat, conversation: convo)
            ctx.insert(msg)
        }
        try? ctx.save()
    }

    private func persistDelegationEvent(from: String, to: String, task: String) {
        guard let ctx = modelContext else { return }

        let convo = Conversation(topic: "\(from) → \(to)")
        convo.parentConversationId = selectedConversationId
        ctx.insert(convo)

        let msg = ConversationMessage(
            text: "[Delegation] \(from) delegated to \(to): \(task)",
            type: .delegation,
            conversation: convo
        )
        ctx.insert(msg)
        try? ctx.save()
    }

    private func persistBlackboardUpdate(key: String, value: String, writtenBy: String) {
        guard let ctx = modelContext else { return }

        let descriptor = FetchDescriptor<BlackboardEntry>(predicate: #Predicate { entry in
            entry.key == key
        })

        if let existing = try? ctx.fetch(descriptor).first {
            existing.value = value
            existing.writtenBy = writtenBy
            existing.updatedAt = Date()
        } else {
            let entry = BlackboardEntry(key: key, value: value, writtenBy: writtenBy)
            ctx.insert(entry)
        }
        try? ctx.save()
    }
}
