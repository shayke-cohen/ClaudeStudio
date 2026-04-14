// Odyssey/Services/MatrixKeychainStore.swift
import Foundation
import Security
import OSLog

private let logger = Logger(subsystem: "com.odyssey.app", category: "MatrixKeychain")

final class MatrixKeychainStore: Sendable {
    private let instanceName: String

    init(instanceName: String) {
        self.instanceName = instanceName
    }

    private var keychainKey: String { "odyssey.matrix.\(instanceName)" }

    // MARK: - Credentials (Keychain)

    func saveCredentials(_ credentials: MatrixCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainKey,
            kSecAttrAccount: "credentials"
        ]
        _ = SecItemDelete(query as CFDictionary)
        let addQuery = query.merging([kSecValueData: data] as [CFString: Any]) { $1 }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func loadCredentials() throws -> MatrixCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainKey,
            kSecAttrAccount: "credentials",
            kSecReturnData: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return try JSONDecoder().decode(MatrixCredentials.self, from: data)
    }

    func deleteCredentials() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainKey,
            kSecAttrAccount: "credentials"
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    // MARK: - Sync token (disk)

    private var syncTokenURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".odyssey/instances/\(instanceName)/matrix-sync-token.txt")
    }

    func saveSyncToken(_ token: String) {
        let url = syncTokenURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? token.write(to: url, atomically: true, encoding: .utf8)
    }

    func loadSyncToken() -> String? {
        (try? String(contentsOf: syncTokenURL, encoding: .utf8))
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty() }
    }

    func deleteSyncToken() {
        try? FileManager.default.removeItem(at: syncTokenURL)
    }
}

private extension String {
    func nilIfEmpty() -> String? { isEmpty ? nil : self }
}
