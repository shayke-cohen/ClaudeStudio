// OdysseyiOS/Services/iOSNostrKeychain.swift
import Foundation
import Security
import P256K

/// Persistent secp256k1 keypair for iOS Nostr identity.
/// Generates once and stores the raw private key bytes in Keychain.
enum iOSNostrKeychain {

    private static let service = "com.odyssey.app.ios.nostr"
    private static let account = "nostr-privkey"

    /// Returns (privkeyHex, pubkeyHex), generating and persisting if needed.
    static func loadOrGenerateKeypair() -> (privkeyHex: String, pubkeyHex: String)? {
        if let privBytes = loadFromKeychain() {
            return keypairFrom(privBytes: privBytes)
        }
        guard let privBytes = generateAndStore() else { return nil }
        return keypairFrom(privBytes: privBytes)
    }

    // MARK: - Private

    private static func keypairFrom(privBytes: Data) -> (privkeyHex: String, pubkeyHex: String)? {
        guard let privkey = try? P256K.Signing.PrivateKey(dataRepresentation: privBytes) else { return nil }
        let pubBytes = Data(privkey.publicKey.xonly.bytes)
        return (privBytes.hexString, pubBytes.hexString)
    }

    private static func loadFromKeychain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    private static func generateAndStore() -> Data? {
        guard let privkey = try? P256K.Signing.PrivateKey() else { return nil }
        let privBytes = Data(privkey.dataRepresentation)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: privBytes,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { return nil }
        return privBytes
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
