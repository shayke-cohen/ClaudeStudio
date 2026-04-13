# Phase 1 — Security Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the sidecar WebSocket safe to expose on a network via Ed25519 identity, bearer token auth, and TLS.

**Architecture:** IdentityManager is a @MainActor singleton that manages all crypto material in Keychain. SidecarManager passes tokens and cert paths as env vars to the sidecar subprocess, then uses them for its own WS connection. The sidecar enforces auth on every new connection.

**Tech Stack:** CryptoKit (Curve25519), Security.framework (Keychain, SecTrust), openssl subprocess (cert generation), Bun TLS (wss://), URLSessionWebSocketTask (wss:// client)

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `Odyssey/Models/UserIdentity.swift` | Codable structs: `UserIdentity`, `AgentIdentityBundle`, `TLSBundle` |
| Create | `Odyssey/Services/IdentityManager.swift` | `@MainActor` singleton — Keychain CRUD, Ed25519 keygen, WS token gen, TLS cert gen |
| Modify | `Odyssey/Models/Agent.swift` | Add `var identityBundleJSON: String? = nil` |
| Modify | `Odyssey/Services/SidecarManager.swift` | Add `instanceName` to Config; wire token + TLS into launch/connect; cert pinning delegate |
| Modify | `sidecar/src/ws-server.ts` | Add `options: { token?, tlsCert?, tlsKey? }` param; enforce bearer auth in `fetch()` handler |
| Modify | `sidecar/src/index.ts` | Read `ODYSSEY_WS_TOKEN`, `ODYSSEY_TLS_CERT`, `ODYSSEY_TLS_KEY` env vars; pass to WsServer |
| Create | `OdysseyTests/IdentityManagerTests.swift` | XCTest: keypair persistence, sign/verify, agent bundle, WS token format/rotation, TLS gen |
| Create | `sidecar/test/unit/ws-auth.test.ts` | Bun test: token enforcement, no-token passthrough |

---

## Task 1: Failing Tests — IdentityManagerTests.swift

Write the Swift XCTest file first. All tests will fail until Task 2 is complete.

**File:** `OdysseyTests/IdentityManagerTests.swift` (create)

- [ ] **Step 1.1: Create `OdysseyTests/IdentityManagerTests.swift`**

```swift
import CryptoKit
import XCTest
@testable import Odyssey

@MainActor
final class IdentityManagerTests: XCTestCase {

    // Use a unique instance name per test run to avoid Keychain collisions
    private let testInstance = "test-\(UUID().uuidString)"

    override func tearDown() async throws {
        // Clean up Keychain entries created during tests so they don't leak
        try? IdentityManager.shared.deleteKeychainItem(
            forKey: "odyssey.identity.\(testInstance)"
        )
        try? IdentityManager.shared.deleteKeychainItem(
            forKey: "odyssey.wstoken.\(testInstance)"
        )
    }

    // MARK: - IM1: Keypair generation and persistence

    func testIM1_keypairGenerationAndPersistence() throws {
        let first = try IdentityManager.shared.userIdentity(for: testInstance)
        let second = try IdentityManager.shared.userIdentity(for: testInstance)
        XCTAssertEqual(first.publicKeyData, second.publicKeyData,
            "Same instance must return same public key bytes on repeated calls")
        XCTAssertEqual(first.publicKeyData.count, 32,
            "Curve25519 public key must be exactly 32 bytes")
    }

    // MARK: - IM2: Sign and verify round-trip

    func testIM2_signAndVerify() throws {
        let identity = try IdentityManager.shared.userIdentity(for: testInstance)
        let payload = Data("hello odyssey".utf8)
        let signature = try IdentityManager.shared.sign(payload, instanceName: testInstance)

        let pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: identity.publicKeyData)
        XCTAssertTrue(pubKey.isValidSignature(signature, for: payload),
            "Signature produced by sign() must verify with the corresponding public key")
    }

    // MARK: - IM3: Agent bundle signature verification

    func testIM3_agentBundleSignature() throws {
        let agentId = UUID()
        let bundle = try IdentityManager.shared.agentBundle(
            for: agentId,
            agentName: "TestAgent",
            instanceName: testInstance
        )

        // Reconstruct the signed message: agentPublicKey ++ agentId.uuidBytes ++ agentName.utf8
        var message = bundle.agentPublicKeyData
        message.append(contentsOf: agentId.uuidBytes)
        message.append(contentsOf: Data("TestAgent".utf8))

        let ownerPubKey = try Curve25519.Signing.PublicKey(rawRepresentation: bundle.ownerPublicKeyData)
        XCTAssertTrue(ownerPubKey.isValidSignature(bundle.ownerSignature, for: message),
            "ownerSignature must be a valid Ed25519 signature over agentPublicKey++agentId++agentName")
    }

    // MARK: - IM4: WS token format — base64, 32 bytes, stable

    func testIM4_wsTokenFormat() throws {
        let token = try IdentityManager.shared.wsToken(for: testInstance)
        guard let decoded = Data(base64Encoded: token) else {
            XCTFail("wsToken must be valid base64")
            return
        }
        XCTAssertEqual(decoded.count, 32, "WS token must decode to exactly 32 bytes")

        let second = try IdentityManager.shared.wsToken(for: testInstance)
        XCTAssertEqual(token, second,
            "Repeated calls to wsToken(for:) must return the same token")
    }

    // MARK: - IM5: WS token rotation produces a new value

    func testIM5_wsTokenRotation() throws {
        let original = try IdentityManager.shared.wsToken(for: testInstance)
        let rotated = try IdentityManager.shared.rotateWSToken(for: testInstance)
        XCTAssertNotEqual(original, rotated,
            "rotateWSToken must produce a different token than the previous one")

        // Clean up rotated token too
        try? IdentityManager.shared.deleteKeychainItem(
            forKey: "odyssey.wstoken.\(testInstance)"
        )
    }

    // MARK: - IM6: Distinct instances have different keys

    func testIM6_distinctInstancesHaveDifferentKeys() throws {
        let instanceA = "\(testInstance)-a"
        let instanceB = "\(testInstance)-b"
        defer {
            try? IdentityManager.shared.deleteKeychainItem(forKey: "odyssey.identity.\(instanceA)")
            try? IdentityManager.shared.deleteKeychainItem(forKey: "odyssey.identity.\(instanceB)")
        }

        let identityA = try IdentityManager.shared.userIdentity(for: instanceA)
        let identityB = try IdentityManager.shared.userIdentity(for: instanceB)
        XCTAssertNotEqual(identityA.publicKeyData, identityB.publicKeyData,
            "Different instance names must produce different keypairs")
    }

    // MARK: - IM7: TLS bundle generation

    func testIM7_tlsBundleGeneration() throws {
        let bundle = try IdentityManager.shared.tlsCertificate(for: testInstance)

        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.certPEMPath),
            "TLS cert PEM file must exist at the returned path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.keyPEMPath),
            "TLS key PEM file must exist at the returned path")
        XCTAssertFalse(bundle.certDERData.isEmpty,
            "certDERData must be non-empty")

        // Calling again must return the same cert (idempotent)
        let bundle2 = try IdentityManager.shared.tlsCertificate(for: testInstance)
        XCTAssertEqual(bundle.certDERData, bundle2.certDERData,
            "Repeated calls must return the cached cert, not regenerate it")

        // Cleanup
        try? FileManager.default.removeItem(atPath: bundle.certPEMPath)
        try? FileManager.default.removeItem(atPath: bundle.keyPEMPath)
    }
}
```

- [ ] **Step 1.2: Confirm tests fail to compile (IdentityManager does not exist yet)**

```bash
cd /Users/shayco/Odyssey && xcodebuild test \
  -scheme Odyssey \
  -destination 'platform=macOS' \
  -only-testing:OdysseyTests/IdentityManagerTests \
  2>&1 | tail -20
```

Expected output: compile error referencing `IdentityManager`, `UserIdentity`, etc.

---

## Task 2: Failing Tests — ws-auth.test.ts

Write the Bun test file first. All tests will fail until Task 3 is complete.

**File:** `sidecar/test/unit/ws-auth.test.ts` (create)

- [ ] **Step 2.1: Create `sidecar/test/unit/ws-auth.test.ts`**

```typescript
/**
 * Unit tests for WsServer bearer token authentication.
 *
 * Tests verify that the WsServer correctly enforces or skips token auth
 * depending on whether the `token` option is configured.
 *
 * Usage: ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) bun test test/unit/ws-auth.test.ts
 */
import { describe, test, expect, afterEach } from "bun:test";
import { WsServer } from "../../src/ws-server.js";
import { SessionManager } from "../../src/session-manager.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import type { SidecarEvent } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";

// Pick a high port range to avoid conflicts with the running app
let portCounter = 19900;
function nextPort(): number {
  return portCounter++;
}

function makeToolContext(): ToolContext {
  const tag = `ws-auth-${Date.now()}`;
  const sessions = new SessionRegistry();
  return {
    blackboard: new BlackboardStore(tag),
    taskBoard: new TaskBoardStore(tag),
    sessions,
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast: (_event: SidecarEvent) => {},
    agentDefinitions: new Map(),
    spawnSession: async (sessionId) => ({ sessionId }),
  };
}

/** Connect a plain WebSocket and return the HTTP upgrade response status.
 *  Returns 101 on successful upgrade, or the HTTP error status on rejection. */
async function connectWithHeaders(
  port: number,
  headers: Record<string, string>
): Promise<number> {
  return new Promise((resolve) => {
    const ws = new WebSocket(`ws://localhost:${port}`, undefined);
    // Bun's WebSocket constructor doesn't expose raw upgrade headers in this way,
    // so we probe via a plain HTTP fetch first.
    // If upgrade is rejected, Bun returns the error status before the WS opens.
    ws.onopen = () => {
      ws.close();
      resolve(101);
    };
    ws.onerror = (event: Event) => {
      // Bun surfaces the status in the error event when the upgrade is rejected
      const wsEvent = event as any;
      resolve(wsEvent.status ?? wsEvent.code ?? 401);
    };
  });
}

/** Attempt an HTTP GET (not an upgrade) and return the status code. */
async function httpGet(port: number, authHeader?: string): Promise<number> {
  const headers: Record<string, string> = {};
  if (authHeader) headers["Authorization"] = authHeader;
  const res = await fetch(`http://localhost:${port}`, { headers });
  return res.status;
}

const servers: WsServer[] = [];

afterEach(() => {
  for (const s of servers) {
    try { s.close(); } catch { /* ignore */ }
  }
  servers.length = 0;
});

// ─── WA1: Reject HTTP upgrade without token ─────────────────────────────────

describe("WsServer bearer token auth", () => {
  test("WA1 rejectsConnectionWithoutToken", async () => {
    const port = nextPort();
    const ctx = makeToolContext();
    const sm = new SessionManager(ctx.broadcast, ctx.sessions, ctx);
    const srv = new WsServer(port, sm, ctx, { token: "secret-token" });
    servers.push(srv);

    // Plain HTTP GET without Authorization header must return 401
    const status = await httpGet(port);
    expect(status).toBe(401);
  });

  // ─── WA2: Reject with wrong token ─────────────────────────────────────────

  test("WA2 rejectsConnectionWithWrongToken", async () => {
    const port = nextPort();
    const ctx = makeToolContext();
    const sm = new SessionManager(ctx.broadcast, ctx.sessions, ctx);
    const srv = new WsServer(port, sm, ctx, { token: "correct-token" });
    servers.push(srv);

    const status = await httpGet(port, "Bearer wrong-token");
    expect(status).toBe(401);
  });

  // ─── WA3: Accept correct token (HTTP path, non-upgrade) returns 426 ───────

  test("WA3 acceptsConnectionWithCorrectToken", async () => {
    const port = nextPort();
    const ctx = makeToolContext();
    const sm = new SessionManager(ctx.broadcast, ctx.sessions, ctx);
    const srv = new WsServer(port, sm, ctx, { token: "correct-token" });
    servers.push(srv);

    // HTTP GET with correct token reaches the WS endpoint (which returns 426 for non-upgrade)
    const status = await httpGet(port, "Bearer correct-token");
    expect(status).toBe(426);
  });

  // ─── WA4: No token configured — all connections pass through ──────────────

  test("WA4 allowsAllConnectionsWhenTokenUnset", async () => {
    const port = nextPort();
    const ctx = makeToolContext();
    const sm = new SessionManager(ctx.broadcast, ctx.sessions, ctx);
    const srv = new WsServer(port, sm, ctx); // no options
    servers.push(srv);

    // No auth header, no token configured — must reach the WS endpoint (426)
    const status = await httpGet(port);
    expect(status).toBe(426);
  });
});
```

- [ ] **Step 2.2: Confirm tests fail (WsServer constructor does not accept options yet)**

```bash
cd /Users/shayco/Odyssey/sidecar && ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) \
  bun test test/unit/ws-auth.test.ts 2>&1 | tail -20
```

Expected output: TypeScript type error — WsServer constructor receives unexpected 4th argument.

---

## Task 3: UserIdentity.swift — Data Structs

Create the value-type structs that `IdentityManager` will produce and consume. No logic here, just types.

**File:** `Odyssey/Models/UserIdentity.swift` (create)

- [ ] **Step 3.1: Create `Odyssey/Models/UserIdentity.swift`**

```swift
import Foundation

// MARK: - UserIdentity

/// Represents the persistent identity of an Odyssey instance (user-level).
/// The private key stays in the Keychain; only the public key is stored here.
struct UserIdentity: Codable, Sendable {
    /// Raw bytes of the Curve25519 Ed25519 signing public key (always 32 bytes).
    let publicKeyData: Data
    /// Human-readable label, defaults to the instance name.
    let displayName: String
    /// When this identity was first generated.
    let createdAt: Date
}

// MARK: - AgentIdentityBundle

/// A verifiable bundle binding an agent's signing key to an owner identity.
/// The owner signs the agent's public key + agent UUID + agent name so that
/// any peer can verify the bundle without trusting the sidecar.
struct AgentIdentityBundle: Codable, Sendable {
    /// Raw bytes of the agent's Curve25519 signing public key.
    let agentPublicKeyData: Data
    /// The SwiftData UUID of the `Agent` model.
    let agentId: UUID
    /// The display name of the agent at bundle creation time.
    let agentName: String
    /// Raw bytes of the owner instance's signing public key.
    let ownerPublicKeyData: Data
    /// Ed25519 signature: owner signs (agentPublicKeyData ++ agentId.uuidBytes ++ agentName.utf8).
    let ownerSignature: Data
    /// When this bundle was created.
    let createdAt: Date
}

// MARK: - TLSBundle

/// Paths and DER bytes for a self-signed P-256 TLS certificate.
/// The cert is generated once per instance and pinned by SidecarManager.
struct TLSBundle: Sendable {
    /// Absolute path to the PEM-encoded certificate file.
    let certPEMPath: String
    /// Absolute path to the PEM-encoded private key file.
    let keyPEMPath: String
    /// DER-encoded certificate bytes — used for cert pinning in URLSessionDelegate.
    let certDERData: Data
}

// MARK: - UUID helpers

extension UUID {
    /// The 16 raw bytes of the UUID, in big-endian network byte order.
    var uuidBytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}
```

- [ ] **Step 3.2: Run `xcodegen generate` to pick up the new file**

```bash
cd /Users/shayco/Odyssey && xcodegen generate 2>&1 | tail -5
```

Expected output: `Writing project to Odyssey.xcodeproj`

---

## Task 4: IdentityManager.swift — Keychain + Crypto Implementation

Implement the full `IdentityManager` singleton. This makes the IM1–IM7 tests pass.

**File:** `Odyssey/Services/IdentityManager.swift` (create)

- [ ] **Step 4.1: Create `Odyssey/Services/IdentityManager.swift`**

```swift
import CryptoKit
import Foundation
import OSLog
import Security

// MARK: - IdentityManager

/// Manages all cryptographic material for Odyssey instances.
///
/// - Ed25519 (Curve25519.Signing) keypairs per instance name — stored in Keychain
/// - 32-byte random WS bearer tokens per instance name — stored in Keychain
/// - Self-signed P-256 TLS certificates per instance name — written to disk, cached in memory
///
/// All methods are safe to call from `@MainActor` code; the Keychain and openssl
/// subprocess calls are synchronous (non-async) since they complete quickly.
@MainActor
final class IdentityManager {

    // MARK: Singleton

    static let shared = IdentityManager()

    private init() {}

    // MARK: - Keychain Constants

    private let keychainService = "com.odyssey.app"

    // MARK: - In-Memory Cache (avoid repeated Keychain roundtrips per session)

    private var identityCache: [String: UserIdentity] = [:]
    private var tokenCache: [String: String] = [:]
    private var tlsCache: [String: TLSBundle] = [:]

    // MARK: - UserIdentity (Ed25519 Keypair)

    /// Load or create the Ed25519 signing keypair for `instanceName`.
    /// The private key is stored in Keychain under `"odyssey.identity.<instanceName>"`.
    /// Returns a `UserIdentity` containing only the public key bytes.
    func userIdentity(for instanceName: String) throws -> UserIdentity {
        if let cached = identityCache[instanceName] { return cached }

        let key = "odyssey.identity.\(instanceName)"

        // Try to load existing private key bytes from Keychain
        if let rawBytes = try? loadKeychainData(forKey: key) {
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawBytes)
            let identity = UserIdentity(
                publicKeyData: Data(privateKey.publicKey.rawRepresentation),
                displayName: instanceName,
                createdAt: Date()
            )
            identityCache[instanceName] = identity
            return identity
        }

        // Generate a new keypair
        let privateKey = Curve25519.Signing.PrivateKey()
        try saveKeychainData(Data(privateKey.rawRepresentation), forKey: key)
        let identity = UserIdentity(
            publicKeyData: Data(privateKey.publicKey.rawRepresentation),
            displayName: instanceName,
            createdAt: Date()
        )
        identityCache[instanceName] = identity
        Log.sidecar.info("IdentityManager: generated new Ed25519 keypair for '\(instanceName, privacy: .public)'")
        return identity
    }

    /// Sign `data` using the Ed25519 private key for `instanceName`.
    func sign(_ data: Data, instanceName: String) throws -> Data {
        let key = "odyssey.identity.\(instanceName)"
        guard let rawBytes = try? loadKeychainData(forKey: key) else {
            // Generate if not present (creates the identity as a side effect)
            _ = try userIdentity(for: instanceName)
            guard let rawBytes2 = try? loadKeychainData(forKey: key) else {
                throw IdentityError.missingPrivateKey(instanceName)
            }
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawBytes2)
            return try Data(privateKey.signature(for: data))
        }
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawBytes)
        return try Data(privateKey.signature(for: data))
    }

    // MARK: - Agent Identity Bundle

    /// Build a signed `AgentIdentityBundle` for an agent owned by `instanceName`.
    /// The agent gets its own freshly-generated Curve25519 keypair.
    /// The owner signs: agentPublicKeyData ++ agentId.uuidBytes ++ agentName.utf8.
    func agentBundle(
        for agentId: UUID,
        agentName: String,
        instanceName: String
    ) throws -> AgentIdentityBundle {
        let ownerIdentity = try userIdentity(for: instanceName)

        // Generate a fresh keypair for this agent
        let agentKey = Curve25519.Signing.PrivateKey()
        let agentPubKeyData = Data(agentKey.publicKey.rawRepresentation)

        // Build the signed message
        var message = agentPubKeyData
        message.append(contentsOf: agentId.uuidBytes)
        message.append(contentsOf: Data(agentName.utf8))

        let signature = try sign(message, instanceName: instanceName)

        return AgentIdentityBundle(
            agentPublicKeyData: agentPubKeyData,
            agentId: agentId,
            agentName: agentName,
            ownerPublicKeyData: ownerIdentity.publicKeyData,
            ownerSignature: signature,
            createdAt: Date()
        )
    }

    // MARK: - WS Bearer Token

    /// Load or create a 32-byte random base64-encoded WS bearer token for `instanceName`.
    /// Stored in Keychain under `"odyssey.wstoken.<instanceName>"`.
    func wsToken(for instanceName: String) throws -> String {
        if let cached = tokenCache[instanceName] { return cached }

        let key = "odyssey.wstoken.\(instanceName)"

        if let stored = try? loadKeychainData(forKey: key),
           let tokenString = String(data: stored, encoding: .utf8) {
            tokenCache[instanceName] = tokenString
            return tokenString
        }

        return try generateAndStoreToken(instanceName: instanceName)
    }

    /// Delete the existing WS token and generate a fresh one.
    @discardableResult
    func rotateWSToken(for instanceName: String) throws -> String {
        tokenCache.removeValue(forKey: instanceName)
        let key = "odyssey.wstoken.\(instanceName)"
        deleteKeychainItem(forKey: key)
        return try generateAndStoreToken(instanceName: instanceName)
    }

    private func generateAndStoreToken(instanceName: String) throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        guard result == errSecSuccess else {
            throw IdentityError.randomGenerationFailed
        }
        let tokenString = Data(bytes).base64EncodedString()
        let key = "odyssey.wstoken.\(instanceName)"
        try saveKeychainData(Data(tokenString.utf8), forKey: key)
        tokenCache[instanceName] = tokenString
        Log.sidecar.info("IdentityManager: generated WS token for '\(instanceName, privacy: .public)'")
        return tokenString
    }

    // MARK: - TLS Certificate

    /// Load or generate a self-signed P-256 TLS certificate for `instanceName`.
    ///
    /// Certificate files are stored at:
    ///   `~/.odyssey/instances/<instanceName>/tls.cert.pem`
    ///   `~/.odyssey/instances/<instanceName>/tls.key.pem`
    ///
    /// Uses `/usr/bin/openssl` subprocess. The generated cert is valid for 10 years
    /// and includes `DNS:localhost,IP:127.0.0.1` SANs.
    func tlsCertificate(for instanceName: String) throws -> TLSBundle {
        if let cached = tlsCache[instanceName] { return cached }

        let dir = "\(NSHomeDirectory())/.odyssey/instances/\(instanceName)"
        let certPath = "\(dir)/tls.cert.pem"
        let keyPath = "\(dir)/tls.key.pem"
        let fm = FileManager.default

        // If cert already exists, read DER bytes and return
        if fm.fileExists(atPath: certPath) && fm.fileExists(atPath: keyPath) {
            let derData = try readDERFromPEM(certPEMPath: certPath)
            let bundle = TLSBundle(certPEMPath: certPath, keyPEMPath: keyPath, certDERData: derData)
            tlsCache[instanceName] = bundle
            return bundle
        }

        // Create the directory
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Generate the certificate with openssl
        try runOpenSSL(args: [
            "req", "-x509", "-nodes", "-days", "3650",
            "-newkey", "ec",
            "-pkeyopt", "ec_paramgen_curve:P-256",
            "-keyout", keyPath,
            "-out", certPath,
            "-subj", "/CN=odyssey-sidecar",
            "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
        ])

        let derData = try readDERFromPEM(certPEMPath: certPath)
        let bundle = TLSBundle(certPEMPath: certPath, keyPEMPath: keyPath, certDERData: derData)
        tlsCache[instanceName] = bundle
        Log.sidecar.info("IdentityManager: generated TLS cert for '\(instanceName, privacy: .public)' at \(dir, privacy: .public)")
        return bundle
    }

    // MARK: - Keychain Helpers

    /// Save raw `data` as a generic password in the Keychain.
    func saveKeychainData(_ data: Data, forKey accountKey: String) throws {
        // Delete any existing item first (update semantics)
        deleteKeychainItem(forKey: accountKey)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: accountKey,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw IdentityError.keychainWriteFailed(status)
        }
    }

    /// Load raw data from the Keychain for `accountKey`, or return nil if absent.
    func loadKeychainData(forKey accountKey: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: accountKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw IdentityError.keychainReadFailed(status)
        }
        return result as? Data
    }

    /// Delete a Keychain item. Non-throwing — missing item is silently ignored.
    @discardableResult
    func deleteKeychainItem(forKey accountKey: String) -> OSStatus {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: accountKey,
        ]
        return SecItemDelete(query as CFDictionary)
    }

    // MARK: - openssl Helpers

    private func runOpenSSL(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "(no stderr)"
            throw IdentityError.opensslFailed(process.terminationStatus, errText)
        }
    }

    private func readDERFromPEM(certPEMPath: String) throws -> Data {
        let tempDER = certPEMPath.replacingOccurrences(of: ".pem", with: ".der")
        defer { try? FileManager.default.removeItem(atPath: tempDER) }
        try runOpenSSL(args: [
            "x509", "-in", certPEMPath, "-outform", "DER", "-out", tempDER,
        ])
        return try Data(contentsOf: URL(fileURLWithPath: tempDER))
    }

    // MARK: - Error Types

    enum IdentityError: Error, LocalizedError {
        case missingPrivateKey(String)
        case keychainWriteFailed(OSStatus)
        case keychainReadFailed(OSStatus)
        case randomGenerationFailed
        case opensslFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .missingPrivateKey(let name):
                return "No private key found for instance '\(name)'"
            case .keychainWriteFailed(let status):
                return "Keychain write failed: OSStatus \(status)"
            case .keychainReadFailed(let status):
                return "Keychain read failed: OSStatus \(status)"
            case .randomGenerationFailed:
                return "SecRandomCopyBytes failed"
            case .opensslFailed(let code, let msg):
                return "openssl exited \(code): \(msg)"
            }
        }
    }
}
```

- [ ] **Step 4.2: Run `xcodegen generate` to pick up IdentityManager.swift**

```bash
cd /Users/shayco/Odyssey && xcodegen generate 2>&1 | tail -5
```

Expected output: `Writing project to Odyssey.xcodeproj`

- [ ] **Step 4.3: Run IM tests — all 7 must pass**

```bash
cd /Users/shayco/Odyssey && xcodebuild test \
  -scheme Odyssey \
  -destination 'platform=macOS' \
  -only-testing:OdysseyTests/IdentityManagerTests \
  2>&1 | grep -E "Test Suite|PASSED|FAILED|error:"
```

Expected output:
```
Test Suite 'IdentityManagerTests' started
Test Case '-[OdysseyTests.IdentityManagerTests testIM1_keypairGenerationAndPersistence]' passed
Test Case '-[OdysseyTests.IdentityManagerTests testIM2_signAndVerify]' passed
Test Case '-[OdysseyTests.IdentityManagerTests testIM3_agentBundleSignature]' passed
Test Case '-[OdysseyTests.IdentityManagerTests testIM4_wsTokenFormat]' passed
Test Case '-[OdysseyTests.IdentityManagerTests testIM5_wsTokenRotation]' passed
Test Case '-[OdysseyTests.IdentityManagerTests testIM6_distinctInstancesHaveDifferentKeys]' passed
Test Case '-[OdysseyTests.IdentityManagerTests testIM7_tlsBundleGeneration]' passed
Test Suite 'IdentityManagerTests' passed
```

---

## Task 5: Agent.swift — Add identityBundleJSON

Add the optional SwiftData field that stores a serialized `AgentIdentityBundle` for each agent.

**File:** `Odyssey/Models/Agent.swift` (modify)

- [ ] **Step 5.1: Add `identityBundleJSON` field to `Agent`**

In `Odyssey/Models/Agent.swift`, after the `var configSlug: String?` line (line 57), add:

```swift
    /// JSON-encoded `AgentIdentityBundle` — populated lazily when the agent is
    /// first provisioned for a network-exposed session. `nil` for local-only agents.
    var identityBundleJSON: String? = nil
```

No migration is needed for SwiftData optional fields with default values.

- [ ] **Step 5.2: Verify the project builds cleanly**

```bash
cd /Users/shayco/Odyssey && xcodebuild build \
  -scheme Odyssey \
  -destination 'platform=macOS' \
  2>&1 | grep -E "BUILD|error:" | tail -10
```

Expected output: `BUILD SUCCEEDED`

---

## Task 6: WsServer — Bearer Token Auth (sidecar/src/ws-server.ts)

Modify `WsServer` to accept an optional `options` parameter with `token`, `tlsCert`, and `tlsKey`. Enforce bearer token auth in the `fetch()` handler before upgrading.

**File:** `sidecar/src/ws-server.ts` (modify)

- [ ] **Step 6.1: Add `WsServerOptions` type and update constructor signature**

At the top of `ws-server.ts`, after the imports block (after line 8), add:

```typescript
export interface WsServerOptions {
  /** If set, every incoming connection must present `Authorization: Bearer <token>`. */
  token?: string;
  /** Absolute path to the PEM-encoded TLS certificate (enables wss://). */
  tlsCert?: string;
  /** Absolute path to the PEM-encoded TLS private key (enables wss://). */
  tlsKey?: string;
}
```

- [ ] **Step 6.2: Update `WsServer` constructor to accept options and enforce auth**

Replace the existing constructor in `ws-server.ts` (lines 15–56):

```typescript
  constructor(
    port: number,
    sessionManager: SessionManager,
    ctx: ToolContext,
    options: WsServerOptions = {}
  ) {
    this.sessionManager = sessionManager;
    this.ctx = ctx;

    // Build the Bun.serve config — add TLS block if cert+key are provided
    const tlsConfig =
      options.tlsCert && options.tlsKey
        ? { cert: Bun.file(options.tlsCert), key: Bun.file(options.tlsKey) }
        : undefined;

    this.server = Bun.serve({
      port,
      ...(tlsConfig ? { tls: tlsConfig } : {}),
      fetch(req, server) {
        // Enforce bearer token if configured
        if (options.token) {
          const authHeader = req.headers.get("authorization") ?? "";
          if (authHeader !== `Bearer ${options.token}`) {
            logger.warn("ws", "Rejected connection: invalid bearer token", {
              remoteAddr: server.requestIP(req)?.address ?? "unknown",
            });
            return new Response("Unauthorized", { status: 401 });
          }
        }

        if (server.upgrade(req)) return undefined;
        return new Response("WebSocket endpoint", { status: 426 });
      },
      websocket: {
        open: (ws) => {
          this.clients.add(ws);
          logger.info("ws", `Swift client connected (total: ${this.clients.size})`);
          const ready: SidecarEvent = {
            type: "sidecar.ready",
            port,
            version: "0.2.0",
          };
          ws.send(JSON.stringify(ready));
        },
        message: (ws, message) => {
          try {
            const data = typeof message === "string" ? message : new TextDecoder().decode(message);
            const command = JSON.parse(data) as SidecarCommand;
            logger.debug("ws", this.describeCommand(command));
            this.handleCommand(command).catch((err) => {
              logger.error("ws", `Command handler error: ${err}`);
            });
          } catch (err) {
            logger.error("ws", `Failed to parse command: ${err}`);
          }
        },
        close: (ws) => {
          this.clients.delete(ws);
          logger.info("ws", `Swift client disconnected (total: ${this.clients.size})`);
        },
      },
    });

    const scheme = tlsConfig ? "wss" : "ws";
    logger.info("ws", `WebSocket server listening on ${scheme}://localhost:${port}`);
  }
```

- [ ] **Step 6.3: Run the WA tests — all 4 must pass**

```bash
cd /Users/shayco/Odyssey/sidecar && ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) \
  bun test test/unit/ws-auth.test.ts 2>&1 | tail -20
```

Expected output:
```
bun test v*
test/unit/ws-auth.test.ts:
✓ WsServer bearer token auth > WA1 rejectsConnectionWithoutToken
✓ WsServer bearer token auth > WA2 rejectsConnectionWithWrongToken
✓ WsServer bearer token auth > WA3 acceptsConnectionWithCorrectToken
✓ WsServer bearer token auth > WA4 allowsAllConnectionsWhenTokenUnset

 4 pass
 0 fail
```

---

## Task 7: index.ts — Wire Token and TLS Env Vars

Pass `ODYSSEY_WS_TOKEN`, `ODYSSEY_TLS_CERT`, and `ODYSSEY_TLS_KEY` from the environment into `WsServer`.

**File:** `sidecar/src/index.ts` (modify)

- [ ] **Step 7.1: Read new env vars and pass to WsServer constructor**

Replace the `WsServer` instantiation line in `index.ts` (line 65):

```typescript
// Before:
const wsServer = new WsServer(WS_PORT, sessionManager, toolContext);
```

```typescript
// After:
const WS_TOKEN = process.env.ODYSSEY_WS_TOKEN ?? process.env.CLAUDESTUDIO_WS_TOKEN;
const TLS_CERT = process.env.ODYSSEY_TLS_CERT ?? process.env.CLAUDESTUDIO_TLS_CERT;
const TLS_KEY = process.env.ODYSSEY_TLS_KEY ?? process.env.CLAUDESTUDIO_TLS_KEY;

const wsServer = new WsServer(WS_PORT, sessionManager, toolContext, {
  ...(WS_TOKEN ? { token: WS_TOKEN } : {}),
  ...(TLS_CERT ? { tlsCert: TLS_CERT } : {}),
  ...(TLS_KEY ? { tlsKey: TLS_KEY } : {}),
});
```

- [ ] **Step 7.2: Verify sidecar compiles cleanly (type-check)**

```bash
cd /Users/shayco/Odyssey/sidecar && bun run --smol src/index.ts --help 2>&1 | head -5 || true
```

Expected: no TypeScript compile errors (the process will start and hang; Ctrl-C is fine in a real session, but in CI just check exit codes).

Alternatively run the full unit suite to confirm no regressions:

```bash
cd /Users/shayco/Odyssey/sidecar && ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) \
  bun test test/unit/ 2>&1 | tail -10
```

Expected: all previously passing unit tests still pass.

---

## Task 8: SidecarManager.swift — instanceName, Token, TLS, and Cert Pinning

Wire everything together in the Swift side: `Config` gets `instanceName`, `launchSidecar()` injects the token and TLS env vars, `connectWebSocket()` adds the `Authorization` header and switches to `wss://`, and the new `URLSessionDelegate` implements cert pinning.

**File:** `Odyssey/Services/SidecarManager.swift` (modify)

- [ ] **Step 8.1: Add `instanceName` to `SidecarManager.Config`**

In `SidecarManager.swift`, replace the `Config` struct (lines 8–17):

```swift
    struct Config: Sendable {
        var wsPort: Int = 9849
        var httpPort: Int = 9850
        var logDirectory: String?
        var dataDirectory: String?
        var bunPathOverride: String?
        var sidecarPathOverride: String?
        var localAgentHostPathOverride: String?
        var mlxRunnerPathOverride: String?
        /// The instance name used for Keychain key namespacing and TLS cert paths.
        /// Defaults to "default" to match the existing log directory convention.
        var instanceName: String = "default"
    }
```

- [ ] **Step 8.2: Add `pinnedCertDERData` property to `SidecarManager`**

In `SidecarManager.swift`, after the `private let hooks: Hooks` line (line 34), add:

```swift
    /// DER bytes of the self-signed TLS cert generated for this instance.
    /// Populated in `launchSidecar()` and used by the URLSessionDelegate for cert pinning.
    private var pinnedCertDERData: Data?
```

- [ ] **Step 8.3: Update `launchSidecar()` to inject token and TLS env vars**

In `launchSidecar()`, after the existing `ODYSSEY_LOG_LEVEL` / `CLAUDESTUDIO_LOG_LEVEL` lines (after line 133), add:

```swift
        // Inject WS bearer token
        if let token = try? IdentityManager.shared.wsToken(for: config.instanceName) {
            process.environment?["ODYSSEY_WS_TOKEN"] = token
            process.environment?["CLAUDESTUDIO_WS_TOKEN"] = token
        }

        // Inject TLS cert + key paths and cache the DER bytes for cert pinning
        if let tlsBundle = try? IdentityManager.shared.tlsCertificate(for: config.instanceName) {
            process.environment?["ODYSSEY_TLS_CERT"] = tlsBundle.certPEMPath
            process.environment?["ODYSSEY_TLS_KEY"] = tlsBundle.keyPEMPath
            process.environment?["CLAUDESTUDIO_TLS_CERT"] = tlsBundle.certPEMPath
            process.environment?["CLAUDESTUDIO_TLS_KEY"] = tlsBundle.keyPEMPath
            self.pinnedCertDERData = tlsBundle.certDERData
        }
```

- [ ] **Step 8.4: Update `connectWebSocket()` to use `wss://` and add the `Authorization` header**

Replace the `connectWebSocket()` method body (lines 193–222):

```swift
    private func connectWebSocket() async throws {
        if let override = hooks.connectWebSocket {
            try await override()
            eventContinuation?.yield(.connected)
            return
        }

        // Cancel any previous connection attempt
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()

        let scheme = (pinnedCertDERData != nil) ? "wss" : "ws"
        let url = URL(string: "\(scheme)://localhost:\(config.wsPort)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        // Add bearer token if available
        if let token = try? IdentityManager.shared.wsToken(for: config.instanceName) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 5
        // Use self as delegate so we can pin the self-signed cert
        let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        self.urlSession = session
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        // Verify connection by receiving the sidecar.ready message
        let message = try await task.receive()
        if case .string(let text) = message {
            Log.sidecar.debug("Handshake received: \(text.prefix(80), privacy: .public)")
        }

        eventContinuation?.yield(.connected)
        receiveMessages()
        startPingPong()
    }
```

- [ ] **Step 8.5: Add `URLSessionDelegate` conformance for cert pinning**

`SidecarManager` is already a `class`, but it needs to conform to `URLSessionDelegate`. Add the conformance at the end of the file, before the final closing brace, in a new extension:

```swift
// MARK: - URLSessionDelegate (cert pinning for self-signed TLS)

extension SidecarManager: URLSessionDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // If no pinned cert is loaded, fall back to default TLS validation
        guard let pinnedData = pinnedCertDERData else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Compare the server's leaf cert DER bytes against our pinned bytes
        let chain = (0..<SecTrustGetCertificateCount(serverTrust))
            .compactMap { SecTrustGetCertificateAtIndex(serverTrust, $0) }

        if let leaf = chain.first {
            let leafData = SecCertificateCopyData(leaf) as Data
            if leafData == pinnedData {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        Log.sidecar.warning("TLS cert pinning failed — cert mismatch")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
```

Note: The `nonisolated` keyword is required because `URLSessionDelegate` callbacks arrive on a non-`@MainActor` queue and `SidecarManager` is `@MainActor`. Accessing `pinnedCertDERData` from a `nonisolated` context requires it to be `Sendable`-safe; since `Data` is `Sendable`, annotate the property with `nonisolated(unsafe) private var pinnedCertDERData: Data?` if the Swift 6 compiler warns about the cross-actor access. In practice, `pinnedCertDERData` is written only during `launchSidecar()` (which completes before any connection is made) and read only in the delegate callback, so the ordering is safe.

Replace the `pinnedCertDERData` declaration added in Step 8.2 with:

```swift
    /// DER bytes of the self-signed TLS cert generated for this instance.
    /// Written in `launchSidecar()` (always before the first connection attempt).
    /// Read in the `URLSessionDelegate` cert-pinning callback. Ordering is safe.
    nonisolated(unsafe) private var pinnedCertDERData: Data?
```

- [ ] **Step 8.6: Add `restart(environmentOverrides:)` convenience method**

After the `stop()` method (after line 78), add:

```swift
    /// Stop the current sidecar, optionally apply config overrides, then restart.
    /// Useful for refreshing TLS certificates or rotating WS tokens at runtime.
    func restart(environmentOverrides: [String: String] = [:]) async {
        stop()
        // Brief pause to let the port be released
        try? await Task.sleep(for: .milliseconds(300))
        try? await start()
    }
```

- [ ] **Step 8.7: Build and verify the full Swift target compiles**

```bash
cd /Users/shayco/Odyssey && xcodebuild build \
  -scheme Odyssey \
  -destination 'platform=macOS' \
  2>&1 | grep -E "BUILD|error:" | tail -10
```

Expected output: `BUILD SUCCEEDED`

---

## Task 9: Full Test Run — Verify No Regressions

Run all tests to confirm nothing was broken by the changes.

- [ ] **Step 9.1: Run all sidecar unit tests**

```bash
cd /Users/shayco/Odyssey/sidecar && ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) \
  bun test test/unit/ 2>&1 | tail -15
```

Expected: all tests pass, including the 4 new `ws-auth.test.ts` tests.

- [ ] **Step 9.2: Run all Swift unit tests**

```bash
cd /Users/shayco/Odyssey && xcodebuild test \
  -scheme Odyssey \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite 'OdysseyTests' (passed|failed)|FAILED|error:" | tail -10
```

Expected: `Test Suite 'OdysseyTests' passed`

- [ ] **Step 9.3: Smoke-test the sidecar boots with token and TLS**

```bash
# Start sidecar with a test token and verify it rejects connections without auth
ODYSSEY_WS_PORT=19849 ODYSSEY_WS_TOKEN=smoketest-token \
  ODYSSEY_DATA_DIR=/tmp/odyssey-smoke-$(date +%s) \
  /opt/homebrew/bin/bun run /Users/shayco/Odyssey/sidecar/src/index.ts &
SIDECAR_PID=$!
sleep 1

# Expect 401 without token
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:19849)
echo "No-auth status: $STATUS"   # expected: 401

# Expect 426 (WS upgrade required) with correct token
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer smoketest-token" http://localhost:19849)
echo "Auth status: $STATUS"   # expected: 426

kill $SIDECAR_PID
```

Expected output:
```
No-auth status: 401
Auth status: 426
```

---

## Task 10: Commit

- [ ] **Step 10.1: Stage all new and modified files**

```bash
cd /Users/shayco/Odyssey && git add \
  Odyssey/Models/UserIdentity.swift \
  Odyssey/Models/Agent.swift \
  Odyssey/Services/IdentityManager.swift \
  Odyssey/Services/SidecarManager.swift \
  sidecar/src/ws-server.ts \
  sidecar/src/index.ts \
  OdysseyTests/IdentityManagerTests.swift \
  sidecar/test/unit/ws-auth.test.ts
```

- [ ] **Step 10.2: Commit**

```bash
cd /Users/shayco/Odyssey && git commit -m "$(cat <<'EOF'
Add Phase 1 security foundation: Ed25519 identity, WS bearer token auth, TLS + cert pinning

- IdentityManager: @MainActor singleton with CryptoKit Curve25519 keypairs,
  32-byte random WS tokens, and openssl P-256 self-signed TLS cert generation;
  all material stored in Keychain under com.odyssey.app
- UserIdentity.swift: Codable structs (UserIdentity, AgentIdentityBundle, TLSBundle)
  plus UUID.uuidBytes helper
- Agent.swift: add identityBundleJSON optional field for future network provisioning
- SidecarManager: inject ODYSSEY_WS_TOKEN + TLS env vars at launch; connect via
  wss:// with Authorization header; URLSessionDelegate pins self-signed leaf cert
- WsServer: new WsServerOptions (token, tlsCert, tlsKey); fetch() enforces bearer
  auth and logs rejections; Bun TLS block wired when cert+key are present
- index.ts: reads ODYSSEY_WS_TOKEN / ODYSSEY_TLS_CERT / ODYSSEY_TLS_KEY env vars
- Tests: IdentityManagerTests (7 XCTest cases), ws-auth.test.ts (4 Bun unit tests)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

Expected output: `[main <sha>] Add Phase 1 security foundation: ...`

---

## Verification Checklist

Before marking Phase 1 complete, confirm every item below:

- [ ] `xcodebuild test -only-testing:OdysseyTests/IdentityManagerTests` — 7/7 pass
- [ ] `bun test test/unit/ws-auth.test.ts` — 4/4 pass
- [ ] `xcodebuild test -scheme Odyssey` — full suite passes (no new failures)
- [ ] `bun test test/unit/` — all unit tests pass (no regressions)
- [ ] Smoke test: sidecar rejects unauthenticated HTTP with 401
- [ ] Smoke test: sidecar accepts bearer-authenticated HTTP with 426
- [ ] `git log --oneline -1` shows the Phase 1 commit

---

## Appendix: Key Design Decisions

### Why `nonisolated(unsafe)` for `pinnedCertDERData`?

Swift 6 strict concurrency requires that `nonisolated` closures (like `URLSessionDelegate` callbacks, which arrive off the main actor) only access `Sendable`-safe storage. `pinnedCertDERData` is a `Data?` (Sendable), but it is a stored property of a `@MainActor`-isolated class. Marking it `nonisolated(unsafe)` is correct here because the write (in `launchSidecar()`) always completes and the sidecar process starts before the first `connectWebSocket()` call can run, so the ordering is correct even without actor hops.

### Why openssl subprocess for TLS?

CryptoKit does not expose P-256 key generation in a form that produces PKCS#8 PEM files, and `Network.framework` TLS configuration requires PEM files for `Bun.serve`. Using `/usr/bin/openssl` (always present on macOS) avoids adding a new Swift package dependency. The cert is generated once and cached; it does not run on every launch.

### Why base64 for WS tokens?

`URLRequest.setValue(_:forHTTPHeaderField:)` requires a `String`. Base64 is ASCII-safe and produces no characters that conflict with HTTP header encoding. The 32 raw bytes give 256-bit entropy before encoding.

### Why skip token auth when `ODYSSEY_WS_TOKEN` is unset?

Backwards compatibility: existing deployments, CI environments, and the `connectWithRetry` fallback path (which connects to an existing sidecar that may not have been launched by the current app instance) must continue to work without auth. Auth is opt-in and defaults to off.
