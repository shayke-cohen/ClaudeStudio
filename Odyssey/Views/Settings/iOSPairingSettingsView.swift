// Odyssey/Views/Settings/iOSPairingSettingsView.swift
import SwiftUI
import SwiftData
import OSLog
import Darwin

private let logger = Logger(subsystem: "com.odyssey.app", category: "iOSPairing")

/// Settings pane for iOS device pairing: QR code display, copy link, and device management.
struct iOSPairingSettingsView: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var p2pNetworkManager: P2PNetworkManager
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<SharedRoomInvite> { $0.pairingType == "device" },
        sort: \SharedRoomInvite.createdAt, order: .reverse
    ) private var deviceInvites: [SharedRoomInvite]

    @State private var currentPayload: InvitePayload? = nil
    @State private var qrImage: CGImage? = nil
    @State private var isGenerating = false
    @State private var generateError: String? = nil
    @State private var allowIOSConnections = false
    @State private var copyConfirmation = false
    @State private var refreshTimer: Timer? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                allowToggleSection
                Divider()
                wanAccessSection
                Divider()
                qrSection
                Divider()
                pairedDevicesSection
            }
            .padding(24)
        }
        .onAppear { startRefreshCycle() }
        .onDisappear { refreshTimer?.invalidate() }
        .stableXrayId("settings.iosPairing.root")
    }

    // MARK: - Allow Toggle

    private var allowToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iOS Connections")
                .font(.headline)
            Toggle("Allow iOS connections", isOn: $allowIOSConnections)
                .onChange(of: allowIOSConnections) { _, newValue in
                    handleAllowToggle(newValue)
                }
                .stableXrayId("settings.iosPairing.allowToggle")
            if allowIOSConnections {
                Text("The sidecar will accept connections from 0.0.0.0 (all interfaces). Ensure your macOS firewall permits incoming TCP connections on port 9849.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .stableXrayId("settings.iosPairing.firewallNote")
            }
        }
    }

    // MARK: - Internet Access Section

    @ViewBuilder
    private var wanAccessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Internet Access")
                .font(.headline)
            switch p2pNetworkManager.wanMappingStatus {
            case .mapped(let ip, let port):
                Label("Internet reachable at \(ip):\(port)", systemImage: "globe")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("settings.ios.wanStatus")
            case .discovering:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking router for automatic port mapping…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("settings.ios.wanStatus")
            case .failed:
                Label("Manual port forwarding required for internet access", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.ios.wanStatus")
            case .idle:
                EmptyView()
            }
        }
    }

    // MARK: - QR Code Section

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair a New Device")
                .font(.headline)
            Text("Scan this QR code from the Odyssey iOS app. The code expires in 5 minutes.")
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
                Text("Failed to generate invite: \(err)")
                    .foregroundStyle(.red)
                    .stableXrayId("settings.iosPairing.qrError")
            }

            HStack(spacing: 12) {
                Button("Refresh QR") {
                    Task { await generateNewInvite() }
                }
                .buttonStyle(.bordered)
                .stableXrayId("settings.iosPairing.refreshQRButton")
                .accessibilityLabel("Refresh QR Code")

                Button(copyConfirmation ? "Copied!" : "Copy Invite Link") {
                    copyInviteLink()
                }
                .buttonStyle(.bordered)
                .disabled(currentPayload == nil)
                .stableXrayId("settings.iosPairing.copyLinkButton")
            }
        }
    }

    // MARK: - Paired Devices Section

    private var pairedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paired Devices")
                .font(.headline)
            if deviceInvites.isEmpty {
                Text("No paired devices yet.")
                    .foregroundStyle(.secondary)
                    .stableXrayId("settings.iosPairing.emptyDeviceList")
            } else {
                ForEach(deviceInvites) { invite in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.recipientLabel ?? "Unknown Device")
                                .font(.body)
                            Text(invite.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revoke") {
                            revokeInvite(invite)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .stableXrayId("settings.iosPairing.revokeButton.\(invite.id.uuidString)")
                        .accessibilityLabel("Revoke pairing for \(invite.recipientLabel ?? "device")")
                    }
                    .padding(.vertical, 4)
                    .stableXrayId("settings.iosPairing.deviceRow.\(invite.id.uuidString)")
                    Divider()
                }
            }
        }
    }

    // MARK: - Actions

    private func startRefreshCycle() {
        Task { await generateNewInvite() }
        let timer = Timer(timeInterval: 270, repeats: true) { _ in
            Task { @MainActor in
                await generateNewInvite()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @MainActor
    private func generateNewInvite() async {
        isGenerating = true
        generateError = nil
        do {
            let wanHint = p2pNetworkManager.natTraversalManager.publicEndpoint
            let lanHint = UPnPPortMapper.localIPAddress()

            let instanceName = appState.sidecarManager?.instanceName ?? "default"
            let wsPort = appState.allocatedWsPort > 0 ? appState.allocatedWsPort : 9849
            let payload = try await InviteCodeGenerator.generateDevice(
                instanceName: instanceName,
                wsPort: wsPort,
                expiresIn: 300,
                singleUse: true,
                lanHint: lanHint,
                wanHint: wanHint
            )
            currentPayload = payload
            qrImage = InviteCodeGenerator.qrCode(for: payload, size: 300)

            let encoded = try InviteCodeGenerator.encode(payload)
            let invite = SharedRoomInvite(
                inviteId: UUID().uuidString,
                inviteToken: payload.wsToken,
                roomId: "",
                inviterUserId: payload.userPublicKey,
                inviterDisplayName: payload.displayName,
                recipientLabel: nil,
                roomTopic: "Device Pairing",
                deepLink: "odyssey://connect?invite=\(encoded)",
                expiresAt: Date(timeIntervalSince1970: payload.exp),
                singleUse: payload.singleUse
            )
            invite.signedPayloadJSON = encoded
            invite.pairingType = "device"
            modelContext.insert(invite)
            try? modelContext.save()

        } catch {
            generateError = error.localizedDescription
            logger.error("iOSPairing invite generation failed: \(error.localizedDescription)")
        }
        isGenerating = false
    }

    private func copyInviteLink() {
        guard let payload = currentPayload,
              let encoded = try? InviteCodeGenerator.encode(payload)
        else { return }
        let link = "odyssey://connect?invite=\(encoded)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        copyConfirmation = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copyConfirmation = false
        }
    }

    private func handleAllowToggle(_ allow: Bool) {
        appState.sidecarManager?.setBindAddress(allow ? "0.0.0.0" : "127.0.0.1")
    }

    private func revokeInvite(_ invite: SharedRoomInvite) {
        invite.status = .revoked
        invite.isRevoked = true
        invite.updatedAt = Date()
        try? modelContext.save()
        let instanceName = appState.sidecarManager?.instanceName ?? "default"
        Task {
            try? IdentityManager.shared.rotateWSToken(for: instanceName)
        }
    }

}
