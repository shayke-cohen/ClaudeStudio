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
