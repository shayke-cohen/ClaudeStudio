import Foundation
import WebKit

/// Manages WKWebsiteDataStore instances for the embedded browser.
/// Default mode is .project — all threads in a project share one cookie store.
@MainActor
final class BrowserSessionStore {

    static let shared = BrowserSessionStore()
    private init() {}

    enum SessionMode: String {
        case project  // one store per project (default)
        case thread   // one store per conversation
    }

    private var stores: [String: WKWebsiteDataStore] = [:]

    /// Returns the appropriate data store for the given key.
    /// For .project mode pass the project's UUID string.
    /// For .thread mode pass the conversation's UUID string.
    func store(for key: String) -> WKWebsiteDataStore {
        if let existing = stores[key] { return existing }
        let store = WKWebsiteDataStore.nonPersistent()
        stores[key] = store
        return store
    }

    /// Clears all cookies and storage for the given key.
    func clearStore(for key: String) async {
        guard let store = stores[key] else { return }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await store.removeData(ofTypes: types, modifiedSince: .distantPast)
        stores.removeValue(forKey: key)
    }

    /// Clears all stores (e.g., on sign-out).
    func clearAll() async {
        for key in stores.keys {
            await clearStore(for: key)
        }
    }
}
