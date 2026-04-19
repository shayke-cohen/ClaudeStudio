// Odyssey/Views/Settings/iOSPairingSettingsView.swift
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.odyssey.app", category: "iOSPairing")

/// Settings pane for iOS device pairing — shows a permanent QR code containing
/// the Mac's Nostr pubkey. No expiry, no TLS certs, no tokens.
struct iOSPairingSettingsView: View {

    @Environment(AppState.self) private var appState

    @State private var qrImage: CGImage? = nil
    @State private var isGenerating = false
    @State private var generateError: String? = nil
    @State private var copyConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                qrSection
            }
            .padding(24)
        }
        .onAppear { generateQR() }
        .stableXrayId("settings.iosPairing.root")
    }

    // MARK: - QR Code Section

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair a New Device")
                .font(.headline)
            Text("Scan this QR code from the Odyssey iOS app. This code is permanent — your Nostr identity doesn't change.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isGenerating {
                ProgressView()
                    .frame(width: 300, height: 300)
                    .stableXrayId("settings.iosPairing.qrLoadingIndicator")
            } else if let cgImage = qrImage {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 300, height: 300)
                    .stableXrayId("settings.iosPairing.qrCodeImage")
                    .accessibilityLabel("Pairing QR Code")
            } else if let err = generateError {
                Text("Failed to generate QR: \(err)")
                    .foregroundStyle(.red)
                    .stableXrayId("settings.iosPairing.qrError")
            }

            HStack(spacing: 12) {
                Button("Refresh QR") {
                    generateQR()
                }
                .buttonStyle(.bordered)
                .stableXrayId("settings.iosPairing.refreshQRButton")
                .accessibilityLabel("Refresh QR Code")

                Button(copyConfirmation ? "Copied!" : "Copy Invite Link") {
                    copyInviteLink()
                }
                .buttonStyle(.bordered)
                .disabled(qrImage == nil)
                .stableXrayId("settings.iosPairing.copyLinkButton")
            }

            if let npub = appState.nostrPublicKeyHex {
                Text("Your npub: \(npub.prefix(16))…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .stableXrayId("settings.iosPairing.npubLabel")
            }
        }
    }

    // MARK: - Actions

    private func generateQR() {
        guard let npub = appState.nostrPublicKeyHex, !npub.isEmpty else {
            generateError = "Nostr identity not ready. Connect the sidecar first."
            return
        }
        isGenerating = true
        generateError = nil
        let instanceName = appState.sidecarManager?.instanceName ?? "default"
        let relays = AppSettings.nostrRelays()
        let payload = InviteCodeGenerator.generateDevice(
            instanceName: instanceName,
            lanHint: nil,
            nostrPubkey: npub,
            nostrRelays: relays
        )
        qrImage = InviteCodeGenerator.qrCode(for: payload, size: 300)
        isGenerating = false
        if qrImage == nil { generateError = "Failed to render QR code." }
    }

    private func copyInviteLink() {
        guard let npub = appState.nostrPublicKeyHex, !npub.isEmpty else { return }
        let instanceName = appState.sidecarManager?.instanceName ?? "default"
        let relays = AppSettings.nostrRelays()
        let payload = InviteCodeGenerator.generateDevice(
            instanceName: instanceName,
            lanHint: nil,
            nostrPubkey: npub,
            nostrRelays: relays
        )
        guard let encoded = try? InviteCodeGenerator.encode(payload) else { return }
        let link = "odyssey://connect?invite=\(encoded)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        copyConfirmation = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copyConfirmation = false
        }
    }
}
