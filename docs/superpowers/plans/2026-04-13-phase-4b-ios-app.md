# Phase 4b — iOS App (RemoteSidecarManager + Views + Tests) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Prerequisite:** Phase 4a must be complete (sidecar stores, REST endpoints, Mac data push, iOS Xcode target created).

**Goal:** Build the iOS thin client: credential storage, remote WS manager, and all screens (conversations, chat, agents, pairing).

**Architecture:** `RemoteSidecarManager` replaces `SidecarManager` on iOS — no subprocess, connects via `wss://` with bearer token + cert pinning. Connection priority: LAN → WAN direct → TURN. `iOSAppState` drives the UI from the event stream. All views are pure SwiftUI reusing OdysseyCore components where possible.

**Tech Stack:** SwiftUI (iOS 17), URLSession (wss://), Network.framework, DataScannerViewController (iOS 16+), Security.framework (Keychain, cert pinning), OdysseyCore package

---

### Task 1: `PeerCredentialStore`

**Files:**
- Create: `OdysseyiOS/Services/PeerCredentialStore.swift`
- Test: `OdysseyiOSTests/PeerCredentialStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// OdysseyiOSTests/PeerCredentialStoreTests.swift
import XCTest
@testable import OdysseyiOS

final class PeerCredentialStoreTests: XCTestCase {
    var store: PeerCredentialStore!
    let testKeychainService = "com.odyssey.app.ios.test-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        store = PeerCredentialStore(keychainService: testKeychainService)
    }

    override func tearDown() {
        try? store.deleteAll()
        super.tearDown()
    }

    func testSaveAndLoad() throws {
        let creds = makeCreds(id: UUID(), name: "My Mac")
        try store.save(creds)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].displayName, "My Mac")
    }

    func testMultiplePeers() throws {
        try store.save(makeCreds(id: UUID(), name: "MacBook Pro"))
        try store.save(makeCreds(id: UUID(), name: "Mac Studio"))
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 2)
    }

    func testDeleteRemovesPeer() throws {
        let creds = makeCreds(id: UUID(), name: "ToDelete")
        try store.save(creds)
        try store.delete(id: creds.id)
        XCTAssertEqual(try store.load().count, 0)
    }

    func testSessionIdPersistence() throws {
        var creds = makeCreds(id: UUID(), name: "Mac")
        try store.save(creds)
        creds.claudeSessionIds["conv-1"] = "claude-session-abc"
        try store.update(creds)
        let loaded = try store.load().first!
        XCTAssertEqual(loaded.claudeSessionIds["conv-1"], "claude-session-abc")
    }

    private func makeCreds(id: UUID, name: String) -> PeerCredentials {
        PeerCredentials(
            id: id, displayName: name,
            userPublicKeyData: Data(repeating: 0, count: 32),
            tlsCertDER: Data(repeating: 1, count: 100),
            wsToken: "test-token", wsPort: 9849,
            lanHint: "192.168.1.5", wanHint: nil, turnConfig: nil,
            pairedAt: Date(), lastConnectedAt: nil, claudeSessionIds: [:]
        )
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OdysseyiOSTests/PeerCredentialStoreTests 2>&1 | tail -10
```
Expected: compile error (type not found)

- [ ] **Step 3: Create `PeerCredentialStore.swift`**

```swift
// OdysseyiOS/Services/PeerCredentialStore.swift
import Foundation
import Security

struct PeerCredentials: Codable, Identifiable {
    let id: UUID
    let displayName: String
    let userPublicKeyData: Data
    let tlsCertDER: Data
    let wsToken: String
    let wsPort: Int
    let lanHint: String?
    let wanHint: String?
    let turnConfig: TURNConfig?
    let pairedAt: Date
    var lastConnectedAt: Date?
    var claudeSessionIds: [String: String]  // conversationId → claudeSessionId
}

final class PeerCredentialStore {
    private let keychainService: String
    private let account = "paired-macs"

    init(keychainService: String = "com.odyssey.app.ios") {
        self.keychainService = keychainService
    }

    func save(_ credentials: PeerCredentials) throws {
        var all = (try? load()) ?? []
        if let idx = all.firstIndex(where: { $0.id == credentials.id }) {
            all[idx] = credentials
        } else {
            all.append(credentials)
        }
        try persist(all)
    }

    func update(_ credentials: PeerCredentials) throws {
        try save(credentials)
    }

    func load() throws -> [PeerCredentials] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return [] }
            throw KeychainError.loadFailed(status)
        }
        return try JSONDecoder().decode([PeerCredentials].self, from: data)
    }

    func delete(id: UUID) throws {
        var all = try load()
        all.removeAll { $0.id == id }
        if all.isEmpty {
            try deleteAll()
        } else {
            try persist(all)
        }
    }

    func deleteAll() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    private func persist(_ credentials: [PeerCredentials]) throws {
        let data = try JSONEncoder().encode(credentials)
        // Try update first, then add
        let updateQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
        ]
        let updateAttrs: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            let addQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: keychainService,
                kSecAttrAccount: account,
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            ]
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.saveFailed(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailed(updateStatus)
        }
    }

    enum KeychainError: Error {
        case loadFailed(OSStatus), saveFailed(OSStatus), deleteFailed(OSStatus)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OdysseyiOSTests/PeerCredentialStoreTests 2>&1 | tail -5
```
Expected: 4 tests PASSED

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey && git add OdysseyiOS/Services/PeerCredentialStore.swift OdysseyiOSTests/PeerCredentialStoreTests.swift
git commit -m "feat(ios): add PeerCredentialStore with Keychain multi-Mac support"
```

---

### Task 2: `RemoteSidecarManager`

**Files:**
- Create: `OdysseyiOS/Services/RemoteSidecarManager.swift`
- Test: `OdysseyiOSTests/RemoteSidecarManagerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// OdysseyiOSTests/RemoteSidecarManagerTests.swift
import XCTest
import Network
@testable import OdysseyiOS

final class RemoteSidecarManagerTests: XCTestCase {
    func testStatusStartsDisconnected() {
        let manager = RemoteSidecarManager()
        XCTAssertEqual(manager.status, .disconnected)
    }

    func testConnectSendsAuthHeader() async throws {
        // Integration test requires a local mock WS server — mark @network
        // Unit test: verify that PeerCredentials.wsToken is used for auth header construction
        let creds = makeCreds(token: "my-secret-token")
        let request = RemoteSidecarManager.buildWSRequest(credentials: creds)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer my-secret-token")
    }

    func testConnectionMethodPreference() {
        // LAN hint should be first attempt
        let creds = makeCreds(lanHint: "192.168.1.5", wanHint: "203.0.113.5:9849")
        let endpoints = RemoteSidecarManager.candidateEndpoints(for: creds)
        XCTAssertTrue(endpoints[0].contains("192.168.1.5"), "LAN should be first")
    }

    private func makeCreds(token: String = "tok", lanHint: String? = nil, wanHint: String? = nil) -> PeerCredentials {
        PeerCredentials(
            id: UUID(), displayName: "Test Mac",
            userPublicKeyData: Data(repeating: 0, count: 32),
            tlsCertDER: Data(repeating: 1, count: 100),
            wsToken: token, wsPort: 9849,
            lanHint: lanHint, wanHint: wanHint, turnConfig: nil,
            pairedAt: Date(), lastConnectedAt: nil, claudeSessionIds: [:]
        )
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OdysseyiOSTests/RemoteSidecarManagerTests 2>&1 | tail -10
```

- [ ] **Step 3: Create `RemoteSidecarManager.swift`**

```swift
// OdysseyiOS/Services/RemoteSidecarManager.swift
import Foundation
import Network
import Combine

@MainActor
final class RemoteSidecarManager: ObservableObject {
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected(method: ConnectionMethod)
    }
    enum ConnectionMethod: String, Equatable { case lan, wanDirect, turn }

    @Published var status: ConnectionStatus = .disconnected
    @Published var connectedPeer: PeerCredentials?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pinnedCertDER: Data?
    private var activeSessions: Set<UUID> = []
    private var eventContinuation: AsyncStream<SidecarEvent>.Continuation?
    private var pingTask: Task<Void, Never>?
    private var pendingCommands: [SidecarCommand] = []
    private var isReconnecting = false

    var events: AsyncStream<SidecarEvent> {
        AsyncStream { continuation in self.eventContinuation = continuation }
    }

    // MARK: - Public API

    func connect(using credentials: PeerCredentials) async {
        status = .connecting
        pinnedCertDER = credentials.tlsCertDER
        connectedPeer = credentials

        for endpoint in Self.candidateEndpoints(for: credentials) {
            do {
                try await connectWebSocket(to: endpoint, credentials: credentials)
                return
            } catch {
                continue  // try next endpoint
            }
        }
        status = .disconnected
    }

    func send(_ command: SidecarCommand) async throws {
        guard let task = webSocketTask else { throw RemoteError.notConnected }
        let data = try command.encodeToJSON()
        guard let text = String(data: data, encoding: .utf8) else { throw RemoteError.encodingFailed }
        try await task.send(.string(text))
    }

    func disconnect() {
        pingTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()
        status = .disconnected
        eventContinuation?.yield(.disconnected)
    }

    func reconnectIfNeeded() async {
        guard case .disconnected = status, let peer = connectedPeer else { return }
        await connect(using: peer)
    }

    /// Called when app goes to background — pauses all active sessions gracefully
    func suspendForBackground() async {
        for sessionId in activeSessions {
            try? await send(.sessionPause(sessionId: sessionId))
        }
        disconnect()
    }

    func trackSession(_ sessionId: UUID) { activeSessions.insert(sessionId) }
    func untrackSession(_ sessionId: UUID) { activeSessions.remove(sessionId) }

    // MARK: - Internal helpers

    static func candidateEndpoints(for credentials: PeerCredentials) -> [String] {
        var endpoints: [String] = []
        if let lan = credentials.lanHint { endpoints.append("\(lan):\(credentials.wsPort)") }
        if let wan = credentials.wanHint { endpoints.append(wan) }
        // TURN appended last — handled differently in connectWebSocket
        return endpoints
    }

    static func buildWSRequest(credentials: PeerCredentials) -> URLRequest {
        let url = URL(string: "wss://localhost:\(credentials.wsPort)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.wsToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func connectWebSocket(to host: String, credentials: PeerCredentials) async throws {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()

        let url = URL(string: "wss://\(host)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.wsToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: CertPinningDelegate(pinnedDER: credentials.tlsCertDER), delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        // Verify handshake
        let message = try await task.receive()
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data),
              case .ready = wire.toEvent() else {
            throw RemoteError.handshakeFailed
        }

        let method: ConnectionMethod = host.contains(credentials.lanHint ?? "NOLAN") ? .lan : .wanDirect
        status = .connected(method: method)
        receiveMessages()
        startPing()
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let msg):
                    self.handleMessage(msg)
                    self.receiveMessages()
                case .failure:
                    self.status = .disconnected
                    self.eventContinuation?.yield(.disconnected)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let t): data = Data(t.utf8)
        case .data(let d): data = d
        @unknown default: return
        }
        guard let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data),
              let event = wire.toEvent() else { return }
        eventContinuation?.yield(event)
    }

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.webSocketTask?.sendPing { _ in }
            }
        }
    }

    enum RemoteError: Error { case notConnected, encodingFailed, handshakeFailed }
}

// MARK: - Cert Pinning Delegate
private final class CertPinningDelegate: NSObject, URLSessionDelegate {
    let pinnedDER: Data
    init(pinnedDER: Data) { self.pinnedDER = pinnedDER }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if let leaf = SecTrustGetCertificateAtIndex(serverTrust, 0) {
            let leafData = SecCertificateCopyData(leaf) as Data
            if leafData == pinnedDER {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
```

> Note: `SidecarCommand.sessionPause` must be added to `SidecarProtocol.swift` if not present. Check the existing enum for `.sessionPause` or equivalent.

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OdysseyiOSTests/RemoteSidecarManagerTests 2>&1 | tail -5
```
Expected: 3 tests PASSED

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey && git add OdysseyiOS/Services/RemoteSidecarManager.swift OdysseyiOSTests/RemoteSidecarManagerTests.swift
git commit -m "feat(ios): add RemoteSidecarManager with wss:// cert pinning and bearer auth"
```

---

### Task 3: `iOSAppState`

**Files:**
- Create: `OdysseyiOS/App/iOSAppState.swift`

- [ ] **Step 1: Create `iOSAppState.swift`**

```swift
// OdysseyiOS/App/iOSAppState.swift
import Foundation
import OdysseyCore

@MainActor
@Observable
final class iOSAppState {
    var conversations: [ConversationSummaryWire] = []
    var streamingBuffers: [String: String] = [:]
    var activeConversationId: String?
    var projects: [ProjectSummaryWire] = []
    var connectionStatus = RemoteSidecarManager.ConnectionStatus.disconnected

    let sidecarManager = RemoteSidecarManager()
    private let credentialStore = PeerCredentialStore()
    private var eventTask: Task<Void, Never>?

    // MARK: - Connect

    func connectToFirstPairedMac() async {
        guard let creds = (try? credentialStore.load())?.first else { return }
        await sidecarManager.connect(using: creds)
        connectionStatus = sidecarManager.status
        startEventLoop()
        await loadConversations()
        await loadProjects()
    }

    // MARK: - Data Loading

    func loadConversations() async {
        guard let baseURL = currentBaseURL() else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/conversations") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        conversations = (try? JSONDecoder().decode([ConversationSummaryWire].self, from: data)) ?? []
    }

    func loadMessages(for conversationId: String) async -> [MessageWire] {
        guard let baseURL = currentBaseURL() else { return [] }
        guard let url = URL(string: "\(baseURL)/api/v1/conversations/\(conversationId)/messages?limit=50") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        return (try? JSONDecoder().decode([MessageWire].self, from: data)) ?? []
    }

    func loadProjects() async {
        guard let baseURL = currentBaseURL() else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/projects") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        projects = (try? JSONDecoder().decode([ProjectSummaryWire].self, from: data)) ?? []
    }

    // MARK: - Session Lifecycle

    func startOrResumeSession(conversationId: String, agentId: String, workingDirectory: String?) async throws {
        let sessionId = UUID()
        var creds = (try? credentialStore.load())?.first(where: {
            $0.claudeSessionIds[conversationId] != nil
        })
        let storedClaudeId = creds?.claudeSessionIds[conversationId]

        let config = AgentConfig(
            name: agentId,
            systemPrompt: nil,
            workingDirectory: workingDirectory,
            skills: [],
            mcpServers: [],
            provider: "system",
            model: "sonnet"
        )

        if let claudeId = storedClaudeId {
            try await sidecarManager.send(.sessionResume(sessionId: sessionId, claudeSessionId: claudeId))
        } else {
            try await sidecarManager.send(.sessionCreate(conversationId: UUID(uuidString: conversationId) ?? UUID(), agentConfig: config))
        }
    }

    // MARK: - Event Loop

    private func startEventLoop() {
        eventTask?.cancel()
        eventTask = Task {
            for await event in sidecarManager.events {
                await handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: SidecarEvent) async {
        switch event {
        case .connected:
            connectionStatus = sidecarManager.status
            await loadConversations()
        case .disconnected:
            connectionStatus = .disconnected
        case .streamToken(let sessionId, let token):
            streamingBuffers[sessionId.uuidString, default: ""] += token
        case .sessionResult(let sessionId, _):
            streamingBuffers.removeValue(forKey: sessionId.uuidString)
            await loadConversations()
        default:
            break
        }
    }

    private func currentBaseURL() -> String? {
        guard let peer = sidecarManager.connectedPeer else { return nil }
        let host = peer.lanHint ?? peer.wanHint?.components(separatedBy: ":").first ?? "localhost"
        return "https://\(host):\(peer.wsPort + 1)"  // HTTP port = WS port + 1
    }
}
```

> Note: Adjust `AgentConfig` initializer, `SidecarCommand` cases, and `SidecarEvent` cases to match the actual types in `SidecarProtocol.swift`.

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild build -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey && git add OdysseyiOS/App/iOSAppState.swift
git commit -m "feat(ios): add iOSAppState with event loop and REST data loading"
```

---

### Task 4: `OdysseyiOSApp.swift` (Full Version)

**Files:**
- Modify: `OdysseyiOS/App/OdysseyiOSApp.swift`

- [ ] **Step 1: Replace placeholder with full app entry point**

```swift
// OdysseyiOS/App/OdysseyiOSApp.swift
import SwiftUI

@main
struct OdysseyiOSApp: App {
    @State private var appState = iOSAppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentRootView()
                .environment(appState)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        Task { await appState.sidecarManager.suspendForBackground() }
                    case .active:
                        Task { await appState.sidecarManager.reconnectIfNeeded() }
                    default: break
                    }
                }
                .task {
                    await appState.connectToFirstPairedMac()
                }
        }
    }
}

struct ContentRootView: View {
    @Environment(iOSAppState.self) private var appState

    var body: some View {
        if appState.connectionStatus == .disconnected,
           (try? PeerCredentialStore().load())?.isEmpty ?? true {
            iOSPairingView()
        } else {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ConversationListView()
                .tabItem { Label("Conversations", systemImage: "bubble.left.and.bubble.right") }
            iOSAgentListView()
                .tabItem { Label("Agents", systemImage: "cpu") }
            iOSSettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey && git add OdysseyiOS/App/OdysseyiOSApp.swift
git commit -m "feat(ios): complete app entry point with scene lifecycle and pairing guard"
```

---

### Task 5: iOS Views

**Files:**
- Create: `OdysseyiOS/Views/iOSPairingView.swift`
- Create: `OdysseyiOS/Views/ConversationListView.swift`
- Create: `OdysseyiOS/Views/iOSChatView.swift`
- Create: `OdysseyiOS/Views/iOSAgentListView.swift`
- Create: `OdysseyiOS/Views/NewConversationSheet.swift`
- Create: `OdysseyiOS/Views/ConnectionStatusView.swift`
- Create: `OdysseyiOS/Views/iOSSettingsView.swift`

- [ ] **Step 1: Create `iOSPairingView.swift`**

```swift
// OdysseyiOS/Views/iOSPairingView.swift
import SwiftUI
import VisionKit

struct iOSPairingView: View {
    @Environment(iOSAppState.self) private var appState
    @State private var showPasteSheet = false
    @State private var pastedLink = ""
    @State private var pairingError: String?
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                Text("Pair with your Mac")
                    .font(.title2.bold())
                Text("Open Odyssey on your Mac, go to Settings → iOS Pairing, and scan the QR code.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerButton { scannedString in
                        Task { await processInvite(scannedString) }
                    }
                    .accessibilityIdentifier("iOSPairing.scannerView")
                }

                Button("Paste Invite Link") {
                    showPasteSheet = true
                }
                .accessibilityIdentifier("iOSPairing.pasteButton")

                if let error = pairingError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .padding()
            .navigationTitle("Connect to Mac")
            .sheet(isPresented: $showPasteSheet) {
                PasteInviteSheet { link in
                    Task { await processInvite(link) }
                }
            }
        }
    }

    private func processInvite(_ raw: String) async {
        isProcessing = true
        pairingError = nil
        defer { isProcessing = false }

        // Extract base64url from odyssey://connect?invite=<payload>
        let payload: String
        if raw.hasPrefix("odyssey://") {
            guard let url = URL(string: raw),
                  let p = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "invite" })?.value else {
                pairingError = "Invalid invite link format"
                return
            }
            payload = p
        } else {
            payload = raw  // assume bare base64url
        }

        do {
            let invitePayload = try InviteCodeGenerator.decode(payload)
            try InviteCodeGenerator.verify(invitePayload)

            let creds = PeerCredentials(
                id: UUID(),
                displayName: invitePayload.displayName,
                userPublicKeyData: Data(base64Encoded: invitePayload.userPublicKey) ?? Data(),
                tlsCertDER: Data(base64Encoded: invitePayload.tlsCertDER) ?? Data(),
                wsToken: invitePayload.wsToken,
                wsPort: invitePayload.wsPort,
                lanHint: invitePayload.hints.lan,
                wanHint: invitePayload.hints.wan,
                turnConfig: invitePayload.hints.turn,
                pairedAt: Date(),
                lastConnectedAt: nil,
                claudeSessionIds: [:]
            )
            try PeerCredentialStore().save(creds)
            await appState.sidecarManager.connect(using: creds)
        } catch {
            pairingError = "Pairing failed: \(error.localizedDescription)"
        }
    }
}

struct PasteInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String) -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite Link") {
                    TextField("odyssey://connect?invite=...", text: $text, axis: .vertical)
                        .accessibilityLabel("Invite Link")
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Paste Invite")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        dismiss()
                        onSubmit(text)
                    }.disabled(text.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct DataScannerButton: View {
    let onScan: (String) -> Void
    @State private var isPresenting = false

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .sheet(isPresented: $isPresenting) {
            DataScannerRepresentable(onScan: { result in
                isPresenting = false
                onScan(result)
            })
        }
    }
}

struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            if case .barcode(let barcode) = addedItems.first {
                onScan(barcode.payloadStringValue ?? "")
            }
        }
    }
}
```

- [ ] **Step 2: Create `ConversationListView.swift`**

```swift
// OdysseyiOS/Views/ConversationListView.swift
import SwiftUI
import OdysseyCore

struct ConversationListView: View {
    @Environment(iOSAppState.self) private var appState
    @State private var showNewConversation = false

    var body: some View {
        NavigationStack {
            List(appState.conversations) { conversation in
                NavigationLink(destination: iOSChatView(conversation: conversation)) {
                    ConversationRow(conversation: conversation)
                }
                .accessibilityIdentifier("iOSConversationList.row.\(conversation.id)")
            }
            .accessibilityIdentifier("iOSConversationList.list")
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewConversation = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("iOSConversationList.newButton")
                }
            }
            .refreshable { await appState.loadConversations() }
            .sheet(isPresented: $showNewConversation) {
                NewConversationSheet()
            }
        }
        .overlay {
            if appState.connectionStatus == .disconnected {
                ConnectionStatusView()
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: ConversationSummaryWire

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.topic).font(.headline).lineLimit(1)
                Spacer()
                if conversation.unread {
                    Circle().fill(.blue).frame(width: 8, height: 8)
                }
            }
            Text(conversation.lastMessagePreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let projectName = conversation.projectName {
                Label(projectName, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 3: Create `iOSChatView.swift`**

```swift
// OdysseyiOS/Views/iOSChatView.swift
import SwiftUI
import OdysseyCore

struct iOSChatView: View {
    @Environment(iOSAppState.self) private var appState
    let conversation: ConversationSummaryWire
    @State private var messages: [MessageWire] = []
    @State private var inputText = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            MessageBubbleSimple(message: message)
                                .id(message.id)
                        }
                        // Streaming indicator
                        if let streaming = appState.streamingBuffers[conversation.id], !streaming.isEmpty {
                            MessageBubbleSimple(message: MessageWire(
                                id: "streaming", text: streaming, type: "text",
                                senderParticipantId: nil,
                                timestamp: ISO8601DateFormatter().string(from: Date()),
                                isStreaming: true
                            ))
                            .id("streaming")
                        }
                    }
                    .padding()
                }
                .accessibilityIdentifier("iOSChat.messageList")
                .onChange(of: messages.count) { _, _ in
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
            }

            Divider()

            HStack(spacing: 12) {
                TextEditor(text: $inputText)
                    .frame(minHeight: 36, maxHeight: 120)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("iOSChat.inputField")

                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("iOSChat.sendButton")
            }
            .padding()
        }
        .navigationTitle(conversation.topic)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMessages() }
    }

    private func loadMessages() async {
        messages = await appState.loadMessages(for: conversation.id)
    }

    private func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        // Optimistically add user message
        messages.append(MessageWire(
            id: UUID().uuidString, text: text, type: "text",
            senderParticipantId: nil,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            isStreaming: false
        ))
        // TODO: find or create session for this conversation, then send session.message
    }
}

struct MessageBubbleSimple: View {
    let message: MessageWire
    private var isUser: Bool { message.senderParticipantId == nil }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isUser ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer(minLength: 60) }
        }
    }
}
```

- [ ] **Step 4: Create remaining views**

```swift
// OdysseyiOS/Views/iOSAgentListView.swift
import SwiftUI

struct AgentListItem: Codable, Identifiable {
    let id: String
    let name: String
    let agentDescription: String
    let icon: String
    let color: String
}

struct iOSAgentListView: View {
    @State private var agents: [AgentListItem] = []
    @Environment(iOSAppState.self) private var appState

    var body: some View {
        NavigationStack {
            List(agents) { agent in
                HStack {
                    Image(systemName: agent.icon)
                        .foregroundStyle(.blue)
                        .frame(width: 32)
                    VStack(alignment: .leading) {
                        Text(agent.name).font(.headline)
                        Text(agent.agentDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .accessibilityIdentifier("iOSAgentList.row.\(agent.id)")
            }
            .accessibilityIdentifier("iOSAgentList.list")
            .navigationTitle("Agents")
            .task { await loadAgents() }
            .refreshable { await loadAgents() }
        }
    }

    private func loadAgents() async {
        guard let peer = appState.sidecarManager.connectedPeer else { return }
        let host = peer.lanHint ?? "localhost"
        guard let url = URL(string: "https://\(host):\(peer.wsPort + 1)/api/v1/agents") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        agents = (try? JSONDecoder().decode([AgentListItem].self, from: data)) ?? []
    }
}

// OdysseyiOS/Views/NewConversationSheet.swift
struct NewConversationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(iOSAppState.self) private var appState
    @State private var selectedProjectId: String?
    @State private var agents: [AgentListItem] = []
    @State private var selectedAgentId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent") {
                    if agents.isEmpty {
                        ProgressView()
                    } else {
                        Picker("Select Agent", selection: $selectedAgentId) {
                            ForEach(agents) { a in
                                Text(a.name).tag(Optional(a.id))
                            }
                        }
                        .accessibilityIdentifier("iOSNewConversation.agentPicker")
                    }
                }
                Section("Project (optional)") {
                    Picker("Project", selection: $selectedProjectId) {
                        Text("No project").tag(Optional<String>.none)
                        ForEach(appState.projects) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                }
            }
            .navigationTitle("New Chat")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Task { await start(); dismiss() }
                    }
                    .disabled(selectedAgentId == nil)
                    .accessibilityIdentifier("iOSNewConversation.confirmButton")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadAgents() }
        }
    }

    private func loadAgents() async {
        guard let peer = appState.sidecarManager.connectedPeer else { return }
        let host = peer.lanHint ?? "localhost"
        guard let url = URL(string: "https://\(host):\(peer.wsPort + 1)/api/v1/agents") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        agents = (try? JSONDecoder().decode([AgentListItem].self, from: data)) ?? []
    }

    private func start() async {
        guard let agentId = selectedAgentId else { return }
        let workDir = appState.projects.first(where: { $0.id == selectedProjectId })?.rootPath
        let convId = UUID().uuidString
        try? await appState.startOrResumeSession(conversationId: convId, agentId: agentId, workingDirectory: workDir)
        await appState.loadConversations()
    }
}

// OdysseyiOS/Views/ConnectionStatusView.swift
struct ConnectionStatusView: View {
    @Environment(iOSAppState.self) private var appState

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "wifi.slash")
                Text("Disconnected from Mac")
                Button("Reconnect") {
                    Task { await appState.sidecarManager.reconnectIfNeeded() }
                }
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
            .accessibilityIdentifier("iOSConnectionStatus.banner")
        }
    }
}

// OdysseyiOS/Views/iOSSettingsView.swift
struct iOSSettingsView: View {
    @Environment(iOSAppState.self) private var appState
    @State private var pairedMacs: [PeerCredentials] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    ConnectionStatusRow(status: appState.connectionStatus)
                }
                Section("Paired Macs") {
                    ForEach(pairedMacs) { mac in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mac.displayName)
                                Text("Last seen: \(mac.lastConnectedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .accessibilityIdentifier("iOSPairing.pairedDeviceRow.\(mac.id.uuidString)")
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            try? PeerCredentialStore().delete(id: pairedMacs[i].id)
                        }
                        pairedMacs.remove(atOffsets: indexSet)
                    }
                }
                Section {
                    NavigationLink("Pair New Mac") { iOSPairingView() }
                }
            }
            .navigationTitle("Settings")
            .onAppear { pairedMacs = (try? PeerCredentialStore().load()) ?? [] }
        }
    }
}

struct ConnectionStatusRow: View {
    let status: RemoteSidecarManager.ConnectionStatus
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(statusLabel)
        }
    }
    private var statusIcon: String {
        switch status {
        case .disconnected: return "wifi.slash"
        case .connecting: return "wifi.exclamationmark"
        case .connected(let m): return m == .lan ? "wifi" : "network"
        }
    }
    private var statusColor: Color {
        switch status {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected: return .green
        }
    }
    private var statusLabel: String {
        switch status {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected(let m): return "Connected (\(m.rawValue))"
        }
    }
}
```

- [ ] **Step 5: Build the full iOS target**

```bash
xcodebuild build -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
cd /Users/shayco/Odyssey && git add OdysseyiOS/Views/
git commit -m "feat(ios): add all Phase 4 views (pairing, conversations, chat, agents, settings)"
```

---

### Task 6: Final Integration Tests

**Files:**
- Test: `OdysseyiOSTests/iOSAppStateTests.swift`

- [ ] **Step 1: Write integration tests**

```swift
// OdysseyiOSTests/iOSAppStateTests.swift
import XCTest
import OdysseyCore
@testable import OdysseyiOS

final class iOSAppStateTests: XCTestCase {
    func testConversationListParsing() throws {
        let json = """
        [{"id":"c1","topic":"Test","lastMessageAt":"2026-04-13T10:00:00Z",
          "lastMessagePreview":"hi","unread":false,"participants":[],
          "projectId":null,"projectName":null,"workingDirectory":null}]
        """.data(using: .utf8)!
        let convs = try JSONDecoder().decode([ConversationSummaryWire].self, from: json)
        XCTAssertEqual(convs.count, 1)
        XCTAssertEqual(convs[0].topic, "Test")
    }

    func testMessageHistoryParsing() throws {
        let json = """
        [{"id":"m1","text":"Hello","type":"text","senderParticipantId":null,
          "timestamp":"2026-04-13T10:00:00Z","isStreaming":false}]
        """.data(using: .utf8)!
        let msgs = try JSONDecoder().decode([MessageWire].self, from: json)
        XCTAssertEqual(msgs[0].text, "Hello")
    }

    func testProjectSummaryParsing() throws {
        let json = """
        [{"id":"p1","name":"MyApp","rootPath":"/Users/test/MyApp",
          "icon":"folder","color":"blue","isPinned":true,"pinnedAgentIds":[]}]
        """.data(using: .utf8)!
        let projs = try JSONDecoder().decode([ProjectSummaryWire].self, from: json)
        XCTAssertEqual(projs[0].rootPath, "/Users/test/MyApp")
    }
}
```

- [ ] **Step 2: Run all iOS tests**

```bash
xcodebuild test -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10
```
Expected: all tests PASSED

- [ ] **Step 3: Run all sidecar tests**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test
```
Expected: all tests PASSED

- [ ] **Step 4: Run macOS tests to check for regressions**

```bash
cd /Users/shayco/Odyssey && xcodebuild test -scheme Odyssey -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

- [ ] **Step 5: Final commit**

```bash
cd /Users/shayco/Odyssey && git add OdysseyiOSTests/
git commit -m "test(ios): add iOSAppState and integration tests for Phase 4b"
```
