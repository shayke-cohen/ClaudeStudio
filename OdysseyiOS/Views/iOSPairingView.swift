// OdysseyiOS/Views/iOSPairingView.swift
import SwiftUI
import OdysseyCore

/// Shown when no Mac is paired yet. Accepts a base64url invite code — either by scanning
/// the QR code shown in Odyssey → Settings → Devices on the Mac, or by pasting it manually.
struct iOSPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var showScanner = false

    let onPaired: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "personalhotspot.circle")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Pair with your Mac")
                        .font(.title2.bold())
                    Text("On your Mac, open Odyssey → Settings → Devices. Scan the QR code or paste the invite code below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // QR scan button
                Button {
                    showScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .accessibilityIdentifier("pairing.scanQRButton")

                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.tertiary)
                    Text("or enter code manually")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                    Rectangle().frame(height: 1).foregroundStyle(.tertiary)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Invite Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $inviteCode)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .accessibilityIdentifier("pairing.inviteCodeField")
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal)

                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .accessibilityIdentifier("pairing.errorLabel")
                }

                Button {
                    Task { await pair() }
                } label: {
                    if isPairing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Pair")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal)
                .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPairing)
                .accessibilityIdentifier("pairing.pairButton")
            }
            .padding(.vertical)
            .navigationTitle("Add Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("pairing.cancelButton")
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet { scannedValue in
                    handleScanned(scannedValue)
                }
            }
            .onOpenURL { url in
                guard url.scheme == "odyssey",
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let inviteParam = components.queryItems?.first(where: { $0.name == "invite" })?.value
                else { return }
                inviteCode = inviteParam
                Task { await pair() }
            }
        }
    }

    private func handleScanned(_ value: String) {
        // Accept either a raw invite code or the full odyssey://connect?invite=<code> deep link
        if let components = URLComponents(string: value),
           components.scheme == "odyssey",
           let invite = components.queryItems?.first(where: { $0.name == "invite" })?.value {
            inviteCode = invite
        } else {
            inviteCode = value
        }
        Task { await pair() }
    }

    // MARK: - Pairing logic

    private func pair() async {
        errorMessage = nil
        isPairing = true
        defer { isPairing = false }

        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let payload = try InvitePayload.decode(code)
            guard !payload.macNpub.isEmpty else {
                throw InviteDecodeError.decodingFailed("Missing Mac Nostr public key")
            }
            let credentials = PeerCredentials(
                id: UUID(),
                displayName: payload.displayName,
                macNostrPubkeyHex: payload.macNpub,
                relayURLs: payload.relays,
                lanHint: payload.lanHint,
                pairedAt: Date(),
                lastConnectedAt: nil,
                claudeSessionIds: [:]
            )
            let store = PeerCredentialStore()
            try store.save(credentials)
            onPaired()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
