import SwiftUI
import SwiftData

struct PeerNetworkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var p2p: P2PNetworkManager
    @Environment(AppState.self) private var appState

    @Query(sort: \NostrPeer.pairedAt, order: .reverse) private var nostrPeers: [NostrPeer]

    @State private var selectedPeerId: String?
    @State private var remoteAgents: [WireAgentExport] = []
    @State private var isLoadingList = false
    @State private var listError: String?
    @State private var importMessage: String?
    @State private var importInFlight = false

    private var selectedPeer: DiscoveredLanPeer? {
        guard let selectedPeerId else { return nil }
        return p2p.peers.first { $0.id == selectedPeerId }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Peer Network")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .xrayId("peerNetwork.title")
                Spacer()
                Circle()
                    .fill(p2p.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                    .xrayId("peerNetwork.statusDot")
                if appState.nostrRelayTotal > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.nostrRelayCount > 0 ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(appState.nostrRelayCount > 0
                             ? "\(appState.nostrRelayCount)/\(appState.nostrRelayTotal) relays"
                             : "Connecting to relays…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("peerNetwork.nostrRelayStatus")
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .xrayId("peerNetwork.closeButton")
                .accessibilityLabel("Close")
            }
            .padding(16)

            Divider()

            if let err = p2p.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(friendlyMessage(for: err))
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button("Try Again") {
                        p2p.stop()
                        p2p.attach(modelContext: modelContext)
                        p2p.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
                .xrayId("peerNetwork.bannerError")
            }

            HSplitView {
                peerListColumn
                    .frame(minWidth: 200, idealWidth: 240)
                detailColumn
                    .frame(minWidth: 320)
            }
            .frame(minHeight: 360)

            Divider()

            HStack {
                Button("Refresh browse") {
                    p2p.stop()
                    p2p.attach(modelContext: modelContext)
                    p2p.start()
                }
                .xrayId("peerNetwork.refreshButton")
                Spacer()
                Text("Advertising local agents for LAN import.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(width: 720, height: 520)
        .onAppear {
            if !p2p.isRunning {
                p2p.attach(modelContext: modelContext)
                p2p.start()
            }
        }
    }

    private var peerListColumn: some View {
        Group {
            if p2p.peers.isEmpty && nostrPeers.isEmpty {
                ContentUnavailableView(
                    "No Peers Found",
                    systemImage: "wifi.exclamationmark",
                    description: Text("Ensure other Macs run Odyssey on the same network or add peers via Nostr invite.")
                )
                .xrayId("peerNetwork.emptyPeers")
            } else {
                List(selection: $selectedPeerId) {
                    if !p2p.peers.isEmpty {
                        Section("Local Network (Bonjour)") {
                            ForEach(p2p.peers, id: \.id) { peer in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.displayName)
                                        .font(.headline)
                                    if !peer.metadata.isEmpty {
                                        Text(peer.metadata)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(peer.id)
                                .xrayId("peerNetwork.peerRow.\(peer.id)")
                            }
                        }
                    }

                    if !nostrPeers.isEmpty {
                        Section("Internet Peers (Nostr)") {
                            ForEach(nostrPeers) { peer in
                                HStack {
                                    Image(systemName: "globe")
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(peer.displayName)
                                            .font(.body)
                                        Text(peer.pubkeyHex.prefix(16) + "…")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospaced()
                                    }
                                    Spacer()
                                    if let lastSeen = peer.lastSeenAt {
                                        Text(lastSeen, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Never seen")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(nostrPeerTag(peer.id))
                                .xrayId("peerNetwork.nostrPeerRow.\(peer.id.uuidString)")
                                .contextMenu {
                                    Button("Copy Pubkey") {
                                        copyToClipboard(peer.pubkeyHex)
                                    }
                                    .xrayId("peerNetwork.copyPubkeyButton.\(peer.id.uuidString)")
                                    Button("Remove Peer", role: .destructive) {
                                        removePeer(peer)
                                    }
                                    .xrayId("peerNetwork.removePeerButton.\(peer.id.uuidString)")
                                }
                            }
                        }
                    }
                }
                .xrayId("peerNetwork.peerList")
            }
        }
        .onChange(of: selectedPeerId) { _, newId in
            if newId != nil {
                remoteAgents = []
                listError = nil
                importMessage = nil
            }
        }
    }

    private var detailColumn: some View {
        Group {
            if let peer = selectedPeer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(peer.displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .xrayId("peerNetwork.detailTitle")
                        Spacer()
                        Label("Relay ready", systemImage: "arrow.left.arrow.right.circle")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .xrayId("peerNetwork.relayStatus")
                    }

                    HStack {
                        Button {
                            Task { await loadAgents(from: peer) }
                        } label: {
                            if isLoadingList {
                                ProgressView("Loading agents…")
                                    .scaleEffect(0.7)
                                    .progressViewStyle(.circular)
                            } else {
                                Text("Browse agents")
                            }
                        }
                        .disabled(isLoadingList)
                        .xrayId("peerNetwork.browseAgentsButton")
                    }

                    if let listError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(friendlyMessage(for: listError))
                                .font(.caption)
                                .lineLimit(2)
                            Spacer()
                            Button("Try Again") {
                                Task { await loadAgents(from: peer) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .xrayId("peerNetwork.listError")
                    }

                    if let importMessage {
                        Text(importMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .xrayId("peerNetwork.importMessage")
                    }

                    List(remoteAgents) { agent in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(agent.name)
                                    .font(.body)
                                Text(AgentDefaults.label(for: agent.model))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Import") {
                                importAgent(agent, peerName: peer.displayName)
                            }
                            .disabled(importInFlight)
                            .xrayId("peerNetwork.importButton.\(agent.id.uuidString)")
                        }
                    }
                    .xrayId("peerNetwork.remoteAgentList")
                }
                .padding()
            } else {
                ContentUnavailableView(
                    "Select a Peer",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Choose an Odyssey instance on your network.")
                )
                .xrayId("peerNetwork.selectPeerPlaceholder")
            }
        }
    }

    private func loadAgents(from peer: DiscoveredLanPeer) async {
        isLoadingList = true
        listError = nil
        defer { isLoadingList = false }
        do {
            remoteAgents = try await p2p.fetchAgents(from: peer)
            if remoteAgents.isEmpty {
                listError = "No agents returned."
            }
        } catch {
            listError = error.localizedDescription
            remoteAgents = []
        }
    }

    private func friendlyMessage(for error: String) -> String {
        let prefixes = ["NSURLErrorDomain", "Error Domain=", "The operation couldn't be completed."]
        var msg = error
        for prefix in prefixes {
            if msg.hasPrefix(prefix) {
                msg = "Network error — check your connection."
                break
            }
        }
        if msg.count > 80 {
            msg = String(msg.prefix(80)) + "…"
        }
        return msg
    }

    private func importAgent(_ w: WireAgentExport, peerName: String) {
        importInFlight = true
        importMessage = nil
        defer { importInFlight = false }
        do {
            let result = try PeerAgentImporter.importFromWire(w, peerDisplayName: peerName, modelContext: modelContext)
            var msg = "Imported \"\(result.agent.name)\"."
            let missing = result.missingSkills + result.missingMCPs + [result.missingPermission].compactMap { $0 }
            if !missing.isEmpty {
                msg += " Missing locally: \(missing.joined(separator: ", "))."
            }
            importMessage = msg
            p2p.refreshExportCache()
        } catch {
            importMessage = error.localizedDescription
        }
    }

    private func removePeer(_ peer: NostrPeer) {
        let name = peer.displayName
        modelContext.delete(peer)
        try? modelContext.save()
        Task {
            try? await appState.sidecarManager?.send(.nostrRemovePeer(name: name))
        }
    }

    private func copyToClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func nostrPeerTag(_ peerId: UUID) -> String {
        "nostr_\(peerId.uuidString)"
    }
}
