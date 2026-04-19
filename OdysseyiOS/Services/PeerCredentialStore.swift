// OdysseyiOS/Services/PeerCredentialStore.swift
import Foundation
import Security

/// Persisted credentials for a paired Mac host.
/// Pairing exchanges only Nostr identities — no TLS certs, no bearer tokens.
public struct PeerCredentials: Codable, Identifiable {
    public let id: UUID
    public let displayName: String
    /// Mac's secp256k1 Nostr pubkey (hex). All communication is E2EE via Nostr relay.
    public let macNostrPubkeyHex: String
    /// Preferred Nostr relay URLs for this peer.
    public let relayURLs: [String]
    /// Optional LAN IP hint for HTTP data-loading (e.g. "192.168.1.42"). No port.
    public let lanHint: String?
    public let pairedAt: Date
    public var lastConnectedAt: Date?
    /// Maps conversationId → claudeSessionId for resume support.
    public var claudeSessionIds: [String: String]

    public init(
        id: UUID,
        displayName: String,
        macNostrPubkeyHex: String,
        relayURLs: [String],
        lanHint: String?,
        pairedAt: Date,
        lastConnectedAt: Date?,
        claudeSessionIds: [String: String]
    ) {
        self.id = id
        self.displayName = displayName
        self.macNostrPubkeyHex = macNostrPubkeyHex
        self.relayURLs = relayURLs
        self.lanHint = lanHint
        self.pairedAt = pairedAt
        self.lastConnectedAt = lastConnectedAt
        self.claudeSessionIds = claudeSessionIds
    }
}

/// Stores and retrieves paired-Mac credentials from the iOS Keychain.
public final class PeerCredentialStore {
    private let keychainService: String
    private let account = "paired-macs"

    public init(keychainService: String = "com.odyssey.app.ios") {
        self.keychainService = keychainService
    }

    // MARK: - Public API

    /// Append or replace a credential entry (matched by `id`).
    public func save(_ credentials: PeerCredentials) throws {
        var all = (try? load()) ?? []
        if let idx = all.firstIndex(where: { $0.id == credentials.id }) {
            all[idx] = credentials
        } else {
            all.append(credentials)
        }
        try persist(all)
    }

    /// Alias for `save(_:)` — update an existing entry.
    public func update(_ credentials: PeerCredentials) throws {
        try save(credentials)
    }

    /// Load all stored credentials. Returns an empty array if none exist.
    public func load() throws -> [PeerCredentials] {
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
        do {
            return try JSONDecoder().decode([PeerCredentials].self, from: data)
        } catch {
            // Stale credentials from an older schema — wipe and return empty so the user re-pairs.
            try? deleteAll()
            return []
        }
    }

    /// Remove the credential with the given id.
    public func delete(id: UUID) throws {
        var all = try load()
        all.removeAll { $0.id == id }
        if all.isEmpty {
            try deleteAll()
        } else {
            try persist(all)
        }
    }

    /// Wipe all stored credentials.
    public func deleteAll() throws {
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

    // MARK: - Private

    private func persist(_ credentials: [PeerCredentials]) throws {
        let data = try JSONEncoder().encode(credentials)
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

    // MARK: - Error

    public enum KeychainError: Error {
        case loadFailed(OSStatus)
        case saveFailed(OSStatus)
        case deleteFailed(OSStatus)
    }
}
