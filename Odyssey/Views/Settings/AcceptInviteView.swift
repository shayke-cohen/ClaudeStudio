// Odyssey/Views/Settings/AcceptInviteView.swift
import SwiftUI
import SwiftData

/// Settings view for pasting an invite code from another Mac to establish
/// a Nostr relay connection.
struct AcceptInviteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var inviteText: String = ""
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle
        case working
        case success(peerName: String)
        case error(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                descriptionSection
                inviteInputSection
                statusSection
            }
            .padding(24)
        }
        .stableXrayId("settings.acceptInvite.root")
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pair with another Mac")
                .font(.headline)
            Text("Paste an invite code you received from another Mac running Odyssey. The code will be decoded, its signature verified, and the peer registered for Nostr relay messaging.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Invite Input

    private var inviteInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite Code")
                .font(.headline)

            TextEditor(text: $inviteText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .accessibilityIdentifier("settings.acceptInvite.textEditor")
                .disabled(status == .working)

            Button(action: acceptInvite) {
                HStack(spacing: 6) {
                    if status == .working {
                        ProgressView().controlSize(.small)
                    }
                    Text("Accept Invite")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(inviteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .working)
            .accessibilityIdentifier("settings.acceptInvite.submitButton")
        }
    }

    // MARK: - Status Feedback

    @ViewBuilder
    private var statusSection: some View {
        switch status {
        case .idle, .working:
            EmptyView()
        case .success(let peerName):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Paired with \(peerName)")
                    .foregroundStyle(.primary)
            }
            .padding(12)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("settings.acceptInvite.success")
        case .error(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.primary)
            }
            .padding(12)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("settings.acceptInvite.error")
        }
    }

    // MARK: - Accept Logic

    private func acceptInvite() {
        status = .working
        let raw = inviteText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract base64 payload from a possible `odyssey://connect?invite=...` URL wrapper
        let base64url: String
        if let url = URL(string: raw),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let inviteItem = components.queryItems?.first(where: { $0.name == "invite" }),
           let value = inviteItem.value {
            base64url = value
        } else {
            base64url = raw
        }

        let payload: InvitePayload
        do {
            payload = try InviteCodeGenerator.decode(base64url)
            try InviteCodeGenerator.verify(payload)
        } catch {
            status = .error("Invalid invite: \(error.localizedDescription)")
            return
        }

        guard let nostrPubkey = payload.nostrPubkey, !nostrPubkey.isEmpty else {
            status = .error("This invite does not include a Nostr pubkey and cannot be used for internet relay.")
            return
        }

        let relays = payload.nostrRelays ?? []
        let displayName = payload.displayName

        // Upsert NostrPeer in SwiftData
        if let existing = NostrPeer.find(pubkeyHex: nostrPubkey, in: modelContext) {
            existing.displayName = displayName
            existing.relays = relays
            existing.pairedAt = Date()
        } else {
            let peer = NostrPeer(
                displayName: displayName,
                pubkeyHex: nostrPubkey,
                relays: relays
            )
            modelContext.insert(peer)
        }
        try? modelContext.save()

        // Register with sidecar (non-fatal if offline)
        Task {
            do {
                try await appState.sidecarManager?.send(.nostrAddPeer(
                    name: displayName,
                    pubkeyHex: nostrPubkey,
                    relays: relays
                ))
                await MainActor.run {
                    status = .success(peerName: displayName)
                    inviteText = ""
                }
            } catch {
                await MainActor.run {
                    // Peer was saved locally; sidecar registration failed (e.g. offline)
                    status = .error("Saved locally but sidecar registration failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
