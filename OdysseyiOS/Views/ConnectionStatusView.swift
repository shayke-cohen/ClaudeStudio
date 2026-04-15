// OdysseyiOS/Views/ConnectionStatusView.swift
import SwiftUI

/// Full-screen or banner view showing the current connection status.
struct ConnectionStatusView: View {
    let status: RemoteSidecarManager.ConnectionStatus
    let onReconnect: () async -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: iconName)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            Text(titleText)
                .font(.title2.bold())

            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if case .disconnected = status {
                Button("Reconnect") {
                    Task { await onReconnect() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("connectionStatus.reconnectButton")
            }

            if case .connecting = status {
                ProgressView()
                    .accessibilityIdentifier("connectionStatus.connectingIndicator")
            }
        }
        .padding()
        .accessibilityIdentifier("connectionStatus.view")
    }

    private var iconName: String {
        switch status {
        case .disconnected: return "wifi.slash"
        case .connecting: return "wifi"
        case .connected: return "wifi"
        }
    }

    private var iconColor: Color {
        switch status {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected: return .green
        }
    }

    private var titleText: String {
        switch status {
        case .disconnected: return "Not Connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        }
    }

    private var subtitleText: String {
        switch status {
        case .disconnected: return "Unable to reach your Mac. Ensure it's on the same network and Odyssey is running."
        case .connecting: return "Establishing a secure connection to your Mac…"
        case .connected(let method):
            switch method {
            case "lan": return "Connected via local network"
            case "wanDirect": return "Connected via internet"
            case "turn": return "Connected via TURN relay"
            default: return "Securely connected to your Mac's Odyssey sidecar."
            }
        }
    }
}
