import Combine
import Foundation
import Network
import OdysseyCore
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
    @Published private(set) var wanMappingStatus: UPnPPortMapper.MappingStatus = .idle
    @Published private(set) var turnStatus: TURNAllocator.AllocatorStatus = .idle

    private var browser: NWBrowser?
    private let server: PeerCatalogServer
    private let browserQueue = DispatchQueue(label: "com.odyssey.p2p.browser")
    private var modelContext: ModelContext?
    weak var sidecarManager: SidecarManager?
    weak var sharedRoomService: SharedRoomService?
    private var previousPeerNames: Set<String> = []
    private let natManager = NATTraversalManager()
    private var natCancellable: AnyCancellable?
    private var stunDiscoveryTask: Task<Void, Never>? = nil
    private let upnpMapper = UPnPPortMapper()
    private var upnpTask: Task<Void, Never>? = nil
    private let turnAllocator = TURNAllocator()
    private var turnAllocationTask: Task<Void, Never>? = nil

    init() {
        let empty = try! JSONEncoder().encode(WireAgentExportList(agents: []))
        server = PeerCatalogServer(initialJSON: empty)
        server.onRoomSyncHint = { [weak self] hint in
            Task { @MainActor in
                await self?.handleRoomSyncHint(hint)
            }
        }
        // NATTraversalManager is @MainActor, so $publicEndpoint already publishes on the main actor.
        // No .receive(on:) needed — removing it avoids a redundant hop and keeps the assignment
        // on the main actor, which is required by nonisolated(unsafe) on publicWANEndpoint.
        natCancellable = natManager.$publicEndpoint
            .sink { [weak self] endpoint in
                self?.server.publicWANEndpoint = endpoint
            }
    }

    /// Exposes the underlying NAT traversal manager for inspection or hole-punching.
    var natTraversalManager: NATTraversalManager { natManager }

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
        let localPort = server.sidecarWsPort ?? 9849
        stunDiscoveryTask = Task {
            await natManager.discoverPublicEndpoint(localPort: localPort)
        }
        upnpTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.upnpMapper.mapPort(localPort)
            // Task inherits @MainActor isolation from start(), so assignments are safe.
            self.wanMappingStatus = result
            if case .mapped(let ip, let port) = result {
                // UPnP confirmed a mapping — use this endpoint instead of the
                // STUN-discovered one because it guarantees the mapping exists.
                self.natManager.setPublicEndpoint("\(ip):\(port)")
            }
        }

        // Start TURN allocation if the user has enabled it in settings.
        let turnEnabled = AppSettings.store.bool(forKey: AppSettings.turnEnabledKey)
        if turnEnabled {
            let url = AppSettings.store.string(forKey: AppSettings.turnURLKey) ?? AppSettings.defaultTurnURL
            let username = AppSettings.store.string(forKey: AppSettings.turnUsernameKey) ?? AppSettings.defaultTurnUsername
            let credential = AppSettings.store.string(forKey: AppSettings.turnCredentialKey) ?? AppSettings.defaultTurnCredential
            let config = OdysseyCore.TURNConfig(url: url, username: username, credential: credential)
            let allocator = turnAllocator
            turnAllocationTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let relay = try await allocator.allocate(config: config)
                    await MainActor.run {
                        self.turnStatus = .allocated(relayEndpoint: relay)
                    }
                } catch {
                    await MainActor.run {
                        self.turnStatus = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    func stop() {
        stunDiscoveryTask?.cancel()
        stunDiscoveryTask = nil
        upnpTask?.cancel()
        upnpTask = nil
        turnAllocationTask?.cancel()
        turnAllocationTask = nil
        browser?.cancel()
        browser = nil
        server.stop()
        peers = []
        isRunning = false
        wanMappingStatus = .idle
        turnStatus = .idle
        // Fire-and-forget removal so we don't block the main actor during teardown
        let mapper = upnpMapper
        let allocator = turnAllocator
        Task.detached {
            await mapper.removeMapping()
            await allocator.stop()
        }
    }

    /// Returns the pre-allocated TURN relay endpoint string if the allocator has succeeded.
    var currentTurnRelay: String? {
        if case .allocated(let relay) = turnStatus { return relay }
        return nil
    }

    /// Re-attempt UPnP/NAT-PMP port mapping. Call this after a network change.
    func refreshWANMapping() async {
        wanMappingStatus = await upnpMapper.renewMapping()
        if case .mapped(let ip, let port) = wanMappingStatus {
            natManager.setPublicEndpoint("\(ip):\(port)")
        }
    }

    func refreshExportCache() {
        guard let ctx = modelContext else { return }
        let data = Self.buildExportData(modelContext: ctx)
        server.updateJSON(data)
    }

    func fetchAgents(from peer: DiscoveredLanPeer) async throws -> [WireAgentExport] {
        try await Self.httpGetAgents(endpoint: peer.endpoint)
    }

    func broadcastRoomSyncHint(roomId: String, hostSequence: Int) async -> Int {
        guard !peers.isEmpty else { return 0 }

        var deliveredCount = 0
        for peer in peers {
            do {
                try await Self.httpSendRoomSyncHint(
                    endpoint: peer.endpoint,
                    roomId: roomId,
                    hostSequence: hostSequence
                )
                deliveredCount += 1
            } catch {
                lastError = error.localizedDescription
            }
        }

        return deliveredCount
    }

    // MARK: - Browser

    private func startBrowser() {
        let params = NWParameters.tcp
        let b = NWBrowser(for: .bonjour(type: "_odyssey._tcp", domain: nil), using: params)
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
        guard let manager = sidecarManager, modelContext != nil else { return agents }
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
                    skills: []
                )
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
                provider: a.provider,
                model: a.model,
                maxTurns: a.maxTurns,
                maxBudget: a.maxBudget,
                maxThinkingTokens: a.maxThinkingTokens,
                icon: a.icon,
                color: a.color,
                defaultWorkingDirectory: a.defaultWorkingDirectory,
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[WireAgentExport], Error>) in
            let fetch = P2PHTTPFetch(endpoint: endpoint, continuation: continuation)
            fetch.start()
        }
    }

    private static func httpSendRoomSyncHint(
        endpoint: NWEndpoint,
        roomId: String,
        hostSequence: Int
    ) async throws {
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? roomId
        let path = "/odyssey/v1/rooms/sync?roomId=\(encodedRoomId)&hostSequence=\(hostSequence)"
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let request = P2PHTTPStatusPing(endpoint: endpoint, path: path, continuation: continuation)
            request.start()
        }
    }

    nonisolated fileprivate static func parseAgentsHTTPResponse(_ data: Data) throws -> [WireAgentExport] {
        guard let str = String(data: data, encoding: .utf8),
              let range = str.range(of: "\r\n\r\n") else {
            throw P2PClientError.invalidResponse
        }
        let body = str[range.upperBound...]
        let bodyData = Data(body.utf8)
        let decoded = try JSONDecoder().decode(WireAgentExportList.self, from: bodyData)
        return decoded.agents
    }

    nonisolated fileprivate static func validateHTTPStatusResponse(_ data: Data) throws {
        guard let str = String(data: data, encoding: .utf8),
              let firstLine = str.components(separatedBy: "\r\n").first,
              !firstLine.isEmpty
        else {
            throw P2PClientError.invalidResponse
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              let statusCode = Int(parts[1]),
              (200..<300).contains(statusCode)
        else {
            throw P2PClientError.invalidResponse
        }
    }

    private func handleRoomSyncHint(_ hint: RoomSyncHint) async {
        guard let modelContext,
              let sharedRoomService
        else { return }

        let descriptor = FetchDescriptor<Conversation>()
        guard let conversation = ((try? modelContext.fetch(descriptor)) ?? []).first(where: { $0.roomId == hint.roomId }),
              conversation.isSharedRoom
        else { return }

        if hint.hostSequence > 0, conversation.lastRoomHostSequence >= hint.hostSequence {
            return
        }

        do {
            try await sharedRoomService.refreshConversation(conversation)
            conversation.roomTransportMode = .direct
            if conversation.roomStatus != .unavailable {
                conversation.roomStatus = .live
            }
            try? modelContext.save()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private let p2pHTTPTimeoutSeconds: Double = 10

/// Sendable helper that owns connection state for a single HTTP GET to a peer.
private final class P2PHTTPFetch: Sendable {
    private let conn: NWConnection
    private let queue = DispatchQueue(label: "com.odyssey.p2p.http.client")
    private let state: P2PHTTPFetchState

    init(endpoint: NWEndpoint, continuation: CheckedContinuation<[WireAgentExport], Error>) {
        self.conn = NWConnection(to: endpoint, using: .tcp)
        self.state = P2PHTTPFetchState(continuation: continuation)
    }

    func start() {
        let conn = self.conn
        let state = self.state
        let receiver = self

        conn.stateUpdateHandler = { connState in
            switch connState {
            case .ready:
                let req = "GET /odyssey/v1/agents HTTP/1.1\r\nHost: odyssey.local\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(req.utf8), completion: .contentProcessed { err in
                    if let err {
                        state.complete(with: .failure(err), conn: conn)
                    } else {
                        receiver.receiveMore()
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

private final class P2PHTTPStatusPing: Sendable {
    private let conn: NWConnection
    private let queue = DispatchQueue(label: "com.odyssey.p2p.http.ping")
    private let state: P2PHTTPStatusPingState
    private let path: String

    init(endpoint: NWEndpoint, path: String, continuation: CheckedContinuation<Void, Error>) {
        self.conn = NWConnection(to: endpoint, using: .tcp)
        self.path = path
        self.state = P2PHTTPStatusPingState(continuation: continuation)
    }

    func start() {
        let conn = self.conn
        let state = self.state
        let requestPath = self.path
        let receiver = self

        conn.stateUpdateHandler = { connState in
            switch connState {
            case .ready:
                let request = "GET \(requestPath) HTTP/1.1\r\nHost: odyssey.local\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(request.utf8), completion: .contentProcessed { error in
                    if let error {
                        state.complete(with: .failure(error), conn: conn)
                    } else {
                        receiver.receiveMore()
                    }
                })
            case .failed(let error):
                state.complete(with: .failure(error), conn: conn)
            default:
                break
            }
        }

        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + p2pHTTPTimeoutSeconds) {
            state.complete(with: .failure(P2PClientError.timeout), conn: conn)
        }
    }

    private func receiveMore() {
        let conn = self.conn
        let state = self.state
        conn.receive(minimumIncompleteLength: 1, maximumLength: 131_072) { [weak self] data, _, isComplete, error in
            if let error {
                state.complete(with: .failure(error), conn: conn)
                return
            }
            if let data, !data.isEmpty {
                state.appendData(data)
            }
            if isComplete {
                do {
                    try P2PNetworkManager.validateHTTPStatusResponse(state.buffer)
                    state.complete(with: .success(()), conn: conn)
                } catch {
                    state.complete(with: .failure(error), conn: conn)
                }
            } else {
                self?.receiveMore()
            }
        }
    }
}

private final class P2PHTTPStatusPingState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<Void, Error>
    private var _buffer = Data()

    var buffer: Data {
        lock.lock()
        let data = _buffer
        lock.unlock()
        return data
    }

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func appendData(_ data: Data) {
        lock.lock()
        _buffer.append(data)
        lock.unlock()
    }

    func complete(with result: Result<Void, Error>, conn: NWConnection) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        guard shouldResume else { return }
        conn.cancel()
        switch result {
        case .success:
            continuation.resume()
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
