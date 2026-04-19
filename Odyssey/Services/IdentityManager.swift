import CryptoKit
import Foundation
import OSLog
import Security
import P256K

// MARK: - Hex helpers

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

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

    // MARK: - Agent Bundle Verification

    /// Verify a peer-supplied `AgentIdentityBundle` using the embedded owner public key.
    /// Returns `true` if the owner signature over (agentPublicKeyData ++ agentId.uuidBytes ++ agentName.utf8) is valid.
    func verifyAgentBundle(_ bundle: AgentIdentityBundle) -> Bool {
        guard let ownerKey = try? Curve25519.Signing.PublicKey(
            rawRepresentation: bundle.ownerPublicKeyData
        ) else { return false }
        var toVerify = Data()
        toVerify.append(bundle.agentPublicKeyData)
        toVerify.append(contentsOf: bundle.agentId.uuidBytes)
        toVerify.append(contentsOf: bundle.agentName.utf8)
        return (try? ownerKey.isValidSignature(bundle.ownerSignature, for: toVerify)) ?? false
    }

    /// Returns a human-readable display name for the owner of `bundle`, or nil if unknown.
    func ownerDisplayName(for bundle: AgentIdentityBundle) -> String? {
        return nil  // Phase 1 TODO: look up by bundle.ownerPublicKeyData fingerprint
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

    // MARK: - Nostr Keypair (secp256k1)

    /// Returns the secp256k1 keypair for Nostr relay, generating and storing it in Keychain on first call.
    /// The key is stored under `"odyssey.nostr.<instanceName>"`.
    /// - Returns: `privkeyHex` is the 32-byte raw private key as hex; `pubkeyHex` is the 32-byte x-only public key as hex (BIP-340 / Nostr convention).
    func nostrKeypair(for instanceName: String) throws -> (privkeyHex: String, pubkeyHex: String) {
        let keychainKey = "odyssey.nostr.\(instanceName)"
        // Try to load existing 32-byte raw private key
        if let rawBytes = try? loadKeychainData(forKey: keychainKey), rawBytes.count == 32 {
            let privkey = try P256K.Signing.PrivateKey(dataRepresentation: rawBytes)
            let pubkeyHex = Data(privkey.publicKey.xonly.bytes).hexString
            return (rawBytes.hexString, pubkeyHex)
        }
        // Generate new keypair
        let privkey = try P256K.Signing.PrivateKey()
        let rawBytes = privkey.dataRepresentation
        try saveKeychainData(rawBytes, forKey: keychainKey)
        let pubkeyHex = Data(privkey.publicKey.xonly.bytes).hexString
        Log.sidecar.info("IdentityManager: generated Nostr secp256k1 keypair for '\(instanceName, privacy: .public)'")
        return (rawBytes.hexString, pubkeyHex)
    }

    /// Deletes the stored Nostr keypair (e.g. on identity reset).
    func deleteNostrKeypair(for instanceName: String) {
        deleteKeychainItem(forKey: "odyssey.nostr.\(instanceName)")
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

        // If cert already exists, check it is RSA (EC certs with explicit curve params
        // are rejected by Bun/BoringSSL, causing the sidecar to fall back to plain ws://
        // while Swift still tries wss:// — resulting in a TLS error on every launch).
        if fm.fileExists(atPath: certPath) && fm.fileExists(atPath: keyPath) {
            let keyContent = (try? String(contentsOfFile: keyPath, encoding: .utf8)) ?? ""
            if keyContent.contains("EC PRIVATE KEY") {
                // Old EC key — delete and regenerate as RSA below
                try? fm.removeItem(atPath: certPath)
                try? fm.removeItem(atPath: keyPath)
                Log.sidecar.warning("IdentityManager: replaced EC cert with RSA for '\(instanceName, privacy: .public)'")
            } else {
                let derData = try readDERFromPEM(certPEMPath: certPath)
                let bundle = TLSBundle(certPEMPath: certPath, keyPEMPath: keyPath, certDERData: derData)
                tlsCache[instanceName] = bundle
                return bundle
            }
        }

        // Create the directory
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Generate the certificate with openssl.
        // Use RSA-2048 — macOS LibreSSL generates EC certs with explicit curve
        // parameters that Bun/BoringSSL rejects (DECODE_ERROR). RSA has no such issue.
        try runOpenSSL(args: [
            "req", "-x509", "-nodes", "-days", "3650",
            "-newkey", "rsa:2048",
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
