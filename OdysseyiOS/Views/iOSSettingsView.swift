// OdysseyiOS/Views/iOSSettingsView.swift
import SwiftUI
import OdysseyCore

struct iOSSettingsView: View {
    @Environment(iOSAppState.self) private var appState
    @State private var pairedMacs: [PeerCredentials] = []
    @State private var showPairingSheet = false
    @State private var errorMessage: String?
    private let store = PeerCredentialStore()

    var body: some View {
        NavigationStack {
            Form {
                // Connection section
                Section("Connection") {
                    ConnectionStatusRow(status: appState.connectionStatus)
                }

                // Paired Macs section
                Section("Paired Macs") {
                    if pairedMacs.isEmpty {
                        Text("No Macs paired yet.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.noPairedMacs")
                    } else {
                        ForEach(pairedMacs) { mac in
                            PairedMacRow(credentials: mac) {
                                unpair(id: mac.id)
                            }
                        }
                        .onDelete { offsets in
                            for idx in offsets {
                                unpair(id: pairedMacs[idx].id)
                            }
                        }
                    }
                    Button {
                        showPairingSheet = true
                    } label: {
                        Label("Add Mac…", systemImage: "plus")
                    }
                    .accessibilityIdentifier("settings.addMacButton")
                }

                // About section
                Section("About") {
                    LabeledContent("Version") {
                        Text(appVersion)
                    }
                    .accessibilityIdentifier("settings.version")
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                            .accessibilityIdentifier("settings.errorLabel")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPairingSheet) {
                iOSPairingView {
                    showPairingSheet = false
                    loadPairedMacs()
                    Task { await appState.connectToFirstPairedMac() }
                }
            }
            .onAppear { loadPairedMacs() }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func loadPairedMacs() {
        pairedMacs = (try? store.load()) ?? []
    }

    private func unpair(id: UUID) {
        do {
            try store.delete(id: id)
            pairedMacs.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Paired Mac row

private struct PairedMacRow: View {
    let credentials: PeerCredentials
    let onUnpair: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(credentials.displayName)
                    .font(.headline)
                if let lan = credentials.lanHint {
                    Text(lan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastSeen = credentials.lastConnectedAt {
                    Text("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                onUnpair()
            } label: {
                Text("Unpair")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Unpair \(credentials.displayName)")
            .accessibilityIdentifier("settings.unpairButton.\(credentials.id)")
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("settings.pairedMacRow.\(credentials.id)")
    }
}
