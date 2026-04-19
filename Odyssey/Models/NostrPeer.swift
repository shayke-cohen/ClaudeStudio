import Foundation
import SwiftData

/// A peer reachable via Nostr relay (internet P2P).
/// Accepted by pasting an invite on the Accept Invite settings view.
/// Differs from LAN `Peer` model in that there is no endpoint URL — routing is via Nostr pubkey + relays.
@Model
final class NostrPeer {
    /// Stable identifier for this peer record.
    var id: UUID = UUID()
    /// Display name from the invite payload (e.g. "Alex's MacBook Pro").
    var displayName: String = ""
    /// 32-byte x-only secp256k1 pubkey as hex (64 chars).
    var pubkeyHex: String = ""
    /// Preferred Nostr relay URLs for this peer.
    var relays: [String] = []
    /// When the invite was accepted.
    var pairedAt: Date = Date()
    /// Last time the sidecar reported receiving a message from this peer (for UI freshness).
    var lastSeenAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        pubkeyHex: String,
        relays: [String],
        pairedAt: Date = Date(),
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.pubkeyHex = pubkeyHex
        self.relays = relays
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
    }
}

// MARK: - Fetch Helpers

extension NostrPeer {
    /// Find an existing NostrPeer by pubkeyHex in the given context.
    static func find(pubkeyHex: String, in context: ModelContext) -> NostrPeer? {
        let descriptor = FetchDescriptor<NostrPeer>(
            predicate: #Predicate { $0.pubkeyHex == pubkeyHex }
        )
        return try? context.fetch(descriptor).first
    }

    /// Find all NostrPeers, sorted by most recently paired.
    static func all(in context: ModelContext) -> [NostrPeer] {
        let descriptor = FetchDescriptor<NostrPeer>(
            sortBy: [SortDescriptor(\.pairedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
