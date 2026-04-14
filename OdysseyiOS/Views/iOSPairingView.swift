// OdysseyiOS/Views/iOSPairingView.swift
import SwiftUI
import OdysseyCore

/// Shown when no Mac is paired yet. Accepts a base64url invite code, decodes and verifies it,
/// then stores the resulting PeerCredentials in the Keychain.
struct iOSPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var pairedSuccessfully = false

    let onPaired: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "personalhotspot.circle")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Pair with your Mac")
                        .font(.title2.bold())
                    Text("On your Mac, open Odyssey → Settings → Devices and tap **Generate Invite**. Paste the code below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

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
                .buttonStyle(.borderedProminent)
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

    // MARK: - Pairing logic

    private func pair() async {
        errorMessage = nil
        isPairing = true
        defer { isPairing = false }

        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let payload = try InvitePayload.decode(code)
            try payload.verify()

            // Decode TLS cert DER
            var certBase64 = payload.tlsCertDERBase64
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let certRemainder = certBase64.count % 4
            if certRemainder != 0 { certBase64 += String(repeating: "=", count: 4 - certRemainder) }
            guard let certDER = Data(base64Encoded: certBase64) else {
                throw InviteDecodeError.invalidBase64
            }

            // Decode host public key
            var pubBase64 = payload.hostPublicKeyBase64url
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let pubRemainder = pubBase64.count % 4
            if pubRemainder != 0 { pubBase64 += String(repeating: "=", count: 4 - pubRemainder) }
            let pubKeyData = Data(base64Encoded: pubBase64) ?? Data()

            let credentials = PeerCredentials(
                id: UUID(),
                displayName: payload.hostDisplayName,
                userPublicKeyData: pubKeyData,
                tlsCertDER: certDER,
                wsToken: payload.bearerToken,
                wsPort: 9849,
                lanHint: payload.hints.lan,
                wanHint: payload.hints.wan,
                turnConfig: payload.turn,
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
