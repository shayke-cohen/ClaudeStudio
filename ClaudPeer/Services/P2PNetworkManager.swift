import Foundation
import Network
import SwiftData

struct DiscoveredLanPeer: Identifiable {
    let id: String
    let displayName: String
    let endpoint: NWEndpoint
    let metadata: String
}

@MainActor
final class P2PNetworkManager: ObservableObject {
    @Published private(set) var peers: [DiscoveredLanPeer] = []
    @Published private(set) var isRunning = false
    @Published var lastError: String?

    private var browser: NWBrowser?
    private let server: PeerCatalogServer
    private let browserQueue = DispatchQueue(label: "com.claudpeer.p2p.browser")
    private var modelContext: ModelContext?
    weak var sidecarManager: SidecarManager?
    private var previousPeerNames: Set<String> = []

    init() {
        let empty = try! JSONEncoder().encode(WireAgentExportList(agents: []))
        server = PeerCatalogServer(initialJSON: empty)
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshExportCache()
    }

    func setSidecarWsPort(_ port: Int) {
        server.sidecarWsPort = port
    }

    func start() {
        guard !isRunning else { return }
        lastError = nil
        do {
            try server.start()
        } catch {
            lastError = error.localizedDescription
            return
        }
        startBrowser()
        isRunning = true
        refreshExportCache()
    }

    func stop() {
        browser?.cancel()
        browser = nil
        server.stop()
        peers = []
        isRunning = false
    }

    func refreshExportCache() {
        guard let ctx = modelContext else { return }
        let data = Self.buildExportData(modelContext: ctx)
        server.updateJSON(data)
    }

    func fetchAgents(from peer: DiscoveredLanPeer) async throws -> [WireAgentExport] {
        try await Self.httpGetAgents(endpoint: peer.endpoint)
    }

    // MARK: - Browser

    private func startBrowser() {
        let params = NWParameters.tcp
        let b = NWBrowser(for: .bonjour(type: "_claudpeer._tcp", domain: nil), using: params)
        b.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                Task { @MainActor in
                    self?.lastError = err.localizedDescription
                }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            Task { @MainActor in
                let newPeers = Self.mapBrowseResults(results)
                self.peers = newPeers
                self.syncPeersToSidecar(newPeers)
            }
        }
        b.start(queue: browserQueue)
        browser = b
    }

    private static func mapBrowseResults(_ results: Set<NWBrowser.Result>) -> [DiscoveredLanPeer] {
        var list: [DiscoveredLanPeer] = []
        let myAdvertisedName = bonjourNameStatic()
        for item in results {
            switch item.endpoint {
            case let .service(name, type, domain, _):
                if name == myAdvertisedName { continue }
                let id = "\(name).\(type).\(domain)"
                list.append(DiscoveredLanPeer(
                    id: id,
                    displayName: name,
                    endpoint: item.endpoint,
                    metadata: ""
                ))
            default:
                break
            }
        }
        list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return list
    }

    private static func bonjourNameStatic() -> String {
        let host = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? "Mac"
        return "\(host)-\(InstanceConfig.name)"
    }

    // MARK: - Sidecar Peer Sync

    /// Notify sidecar of peer additions/removals so PeerBus tools can see remote agents.
    private func syncPeersToSidecar(_ currentPeers: [DiscoveredLanPeer]) {
        guard let manager = sidecarManager else { return }
        let currentNames = Set(currentPeers.map(\.displayName))

        // Peers that disappeared
        for removed in previousPeerNames.subtracting(currentNames) {
            Task {
                try? await manager.send(.peerRemove(name: removed))
            }
        }

        previousPeerNames = currentNames
        // For new/existing peers, registration happens when agents are fetched (via fetchAndRegisterPeer)
    }

    /// Fetch a peer's agent catalog and register it with the sidecar.
    func fetchAndRegisterPeer(_ peer: DiscoveredLanPeer, wsPort: Int) async throws -> [WireAgentExport] {
        let agents = try await Self.httpGetAgents(endpoint: peer.endpoint)
        guard let manager = sidecarManager, let ctx = modelContext else { return agents }

        let provisioner = AgentProvisioner(modelContext: ctx)
        let defs: [AgentDefinitionWire] = agents.map { a in
            AgentDefinitionWire(
                name: a.name,
                config: AgentConfig(
                    name: a.name,
                    systemPrompt: a.systemPrompt,
                    allowedTools: [],
                    mcpServers: [],
                    model: a.model,
                    maxTurns: a.maxTurns,
                    maxBudget: a.maxBudget,
                    maxThinkingTokens: a.maxThinkingTokens,
                    workingDirectory: a.defaultWorkingDirectory ?? "",
                    skills: [],
                    instancePolicyKind: a.instancePolicyKind,
                    instancePolicyPoolMax: a.instancePolicyPoolMax
                ),
                instancePolicy: a.instancePolicyKind
            )
        }

        let endpoint = "ws://\(peer.displayName):\(wsPort)"
        try? await manager.send(.peerRegister(name: peer.displayName, endpoint: endpoint, agents: defs))
        return agents
    }

    // MARK: - Export

    private static func buildExportData(modelContext: ModelContext) -> Data {
        let desc = FetchDescriptor<Agent>(sortBy: [SortDescriptor(\.name)])
        let agents = (try? modelContext.fetch(desc)) ?? []
        let skills = (try? modelContext.fetch(FetchDescriptor<Skill>())) ?? []
        let mcps = (try? modelContext.fetch(FetchDescriptor<MCPServer>())) ?? []
        let perms = (try? modelContext.fetch(FetchDescriptor<PermissionSet>())) ?? []

        let skillById = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        let mcpById = Dictionary(uniqueKeysWithValues: mcps.map { ($0.id, $0) })
        let permById = Dictionary(uniqueKeysWithValues: perms.map { ($0.id, $0) })

        let exports: [WireAgentExport] = agents.map { a in
            let skillNames = a.skillIds.compactMap { skillById[$0]?.name }
            let mcpNames = a.extraMCPServerIds.compactMap { mcpById[$0]?.name }
            let permName = a.permissionSetId.flatMap { permById[$0]?.name }
            return WireAgentExport(
                id: a.id,
                name: a.name,
                agentDescription: a.agentDescription,
                systemPrompt: a.systemPrompt,
                model: a.model,
                maxTurns: a.maxTurns,
                maxBudget: a.maxBudget,
                maxThinkingTokens: a.maxThinkingTokens,
                icon: a.icon,
                color: a.color,
                instancePolicyKind: a.instancePolicyKind,
                instancePolicyPoolMax: a.instancePolicyPoolMax,
                defaultWorkingDirectory: a.defaultWorkingDirectory,
                githubRepo: a.githubRepo,
                githubDefaultBranch: a.githubDefaultBranch,
                skillNames: skillNames,
                extraMCPNames: mcpNames,
                permissionSetName: permName
            )
        }
        // Export groups
        let groupDesc = FetchDescriptor<AgentGroup>(sortBy: [SortDescriptor(\.sortOrder)])
        let groupEntities = (try? modelContext.fetch(groupDesc)) ?? []
        let agentNameById = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.name) })
        let groupExports: [WireGroupExport] = groupEntities
            .filter { $0.originKind != "peer" }
            .map { g in
                WireGroupExport(
                    id: g.id,
                    name: g.name,
                    groupDescription: g.groupDescription,
                    icon: g.icon,
                    color: g.color,
                    groupInstruction: g.groupInstruction,
                    defaultMission: g.defaultMission,
                    agentNames: g.agentIds.compactMap { agentNameById[$0] }
                )
            }

        let list = WireAgentExportList(agents: exports, groups: groupExports)
        return (try? JSONEncoder().encode(list)) ?? Data("{\"agents\":[]}".utf8)
    }

    // MARK: - HTTP over NWConnection

    private static func httpGetAgents(endpoint: NWEndpoint) async throws -> [WireAgentExport] {
        try await withCheckedThrowingContinuation { continuation in
            let fetch = P2PHTTPFetch(endpoint: endpoint, continuation: continuation)
            fetch.start()
        }
    }

    fileprivate static func parseAgentsHTTPResponse(_ data: Data) throws -> [WireAgentExport] {
        guard let str = String(data: data, encoding: .utf8),
              let range = str.range(of: "\r\n\r\n") else {
            throw P2PClientError.invalidResponse
        }
        let body = str[range.upperBound...]
        let bodyData = Data(body.utf8)
        let decoded = try JSONDecoder().decode(WireAgentExportList.self, from: bodyData)
        return decoded.agents
    }
}

private let p2pHTTPTimeoutSeconds: Double = 10

/// Sendable helper that owns connection state for a single HTTP GET to a peer.
private final class P2PHTTPFetch: Sendable {
    private let conn: NWConnection
    private let queue = DispatchQueue(label: "com.claudpeer.p2p.http.client")
    private let state: P2PHTTPFetchState

    init(endpoint: NWEndpoint, continuation: CheckedContinuation<[WireAgentExport], Error>) {
        self.conn = NWConnection(to: endpoint, using: .tcp)
        self.state = P2PHTTPFetchState(continuation: continuation)
    }

    func start() {
        let conn = self.conn
        let state = self.state

        conn.stateUpdateHandler = { [weak self] connState in
            switch connState {
            case .ready:
                let req = "GET /claudpeer/v1/agents HTTP/1.1\r\nHost: claudpeer.local\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(req.utf8), completion: .contentProcessed { err in
                    if let err {
                        state.complete(with: .failure(err), conn: conn)
                    } else {
                        self?.receiveMore()
                    }
                })
            case .failed(let err):
                state.complete(with: .failure(err), conn: conn)
            default:
                break
            }
        }

        conn.start(queue: queue)

        // Timeout
        queue.asyncAfter(deadline: .now() + p2pHTTPTimeoutSeconds) {
            state.complete(with: .failure(P2PClientError.timeout), conn: conn)
        }
    }

    private func receiveMore() {
        let conn = self.conn
        let state = self.state
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            if let error {
                state.complete(with: .failure(error), conn: conn)
                return
            }
            if let data, !data.isEmpty {
                state.appendData(data)
            }
            if isComplete {
                do {
                    let agents = try P2PNetworkManager.parseAgentsHTTPResponse(state.buffer)
                    state.complete(with: .success(agents), conn: conn)
                } catch {
                    state.complete(with: .failure(error), conn: conn)
                }
            } else {
                self?.receiveMore()
            }
        }
    }
}

/// Thread-safe mutable state for P2PHTTPFetch.
private final class P2PHTTPFetchState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<[WireAgentExport], Error>
    private var _buffer = Data()

    var buffer: Data {
        lock.lock()
        let d = _buffer
        lock.unlock()
        return d
    }

    init(continuation: CheckedContinuation<[WireAgentExport], Error>) {
        self.continuation = continuation
    }

    func appendData(_ data: Data) {
        lock.lock()
        _buffer.append(data)
        lock.unlock()
    }

    func complete(with result: Result<[WireAgentExport], Error>, conn: NWConnection) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        guard shouldResume else { return }
        conn.cancel()
        switch result {
        case .success(let agents):
            continuation.resume(returning: agents)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

enum P2PClientError: LocalizedError {
    case invalidResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not read agent list from peer."
        case .timeout:
            return "Peer did not respond in time."
        }
    }
}

