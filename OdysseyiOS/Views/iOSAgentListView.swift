// OdysseyiOS/Views/iOSAgentListView.swift
import SwiftUI
import OdysseyCore

// MARK: - Agent wire type (thin representation from REST API)

/// Thin agent summary fetched from GET /api/v1/agents.
struct AgentSummaryWire: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: String
    let model: String
}

// MARK: - Helper types

struct AgentListItem: View {
    let agent: AgentSummaryWire
    let onStartConversation: (AgentSummaryWire) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: agent.color) ?? .blue)
                    .frame(width: 44, height: 44)
                Text(agent.icon)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.headline)
                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                onStartConversation(agent)
            } label: {
                Image(systemName: "plus.bubble")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start conversation with \(agent.name)")
            .accessibilityIdentifier("agentList.startButton.\(agent.id)")
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("agentList.row.\(agent.id)")
    }
}

struct NewConversationSheet: View {
    let agent: AgentSummaryWire
    @Environment(iOSAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var initialMessage = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Agent") {
                    HStack {
                        Text(agent.icon)
                        Text(agent.name)
                            .font(.headline)
                    }
                }
                Section("Initial Message (optional)") {
                    TextField("Type a message…", text: $initialMessage, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("newConversation.messageField")
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                            .accessibilityIdentifier("newConversation.errorLabel")
                    }
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("newConversation.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Task { await create() }
                    }
                    .disabled(isCreating)
                    .accessibilityIdentifier("newConversation.startButton")
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        errorMessage = nil
        do {
            // Use a new UUID as the conversation id
            let conversationId = UUID().uuidString
            try await appState.startOrResumeSession(
                conversationId: conversationId,
                agentId: agent.id,
                workingDirectory: nil
            )
            if !initialMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await appState.send(initialMessage, to: conversationId)
            }
            await appState.loadConversations()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ConnectionStatusRow: View {
    let status: RemoteSidecarManager.ConnectionStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("connectionStatus.badge")
        .accessibilityLabel("Connection: \(statusLabel)")
    }

    private var statusLabel: String {
        switch status {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected(let method): return "Connected (\(method))"
        }
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected: return .green
        }
    }
}

// MARK: - Main view

struct iOSAgentListView: View {
    @Environment(iOSAppState.self) private var appState
    @State private var agents: [AgentSummaryWire] = []
    @State private var selectedAgent: AgentSummaryWire?
    @State private var isLoadingAgents = false

    var body: some View {
        NavigationView {
            Group {
                if isLoadingAgents {
                    ProgressView("Loading agents…")
                        .accessibilityIdentifier("agentList.loadingIndicator")
                } else if agents.isEmpty {
                    ContentUnavailableView(
                        "No Agents",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Connect to your Mac to see available agents.")
                    )
                    .accessibilityIdentifier("agentList.emptyState")
                } else {
                    List(agents) { agent in
                        AgentListItem(agent: agent) { selected in
                            selectedAgent = selected
                        }
                    }
                    .accessibilityIdentifier("agentList.list")
                }
            }
            .navigationTitle("Agents")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ConnectionStatusRow(status: appState.connectionStatus)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await loadAgents() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("agentList.refreshButton")
                    .accessibilityLabel("Refresh agents")
                }
            }
        }
        .sheet(item: $selectedAgent) { agent in
            NewConversationSheet(agent: agent)
                .environment(appState)
        }
        .task {
            await loadAgents()
        }
    }

    private func loadAgents() async {
        guard case .connected = appState.connectionStatus,
              let peer = appState.sidecarManager.connectedPeer else { return }
        let host = peer.lanHint?.components(separatedBy: ":").first
            ?? peer.wanHint?.components(separatedBy: ":").first
            ?? "localhost"
        let httpPort = peer.wsPort + 1
        guard let url = URL(string: "https://\(host):\(httpPort)/api/v1/agents") else { return }
        isLoadingAgents = true
        defer { isLoadingAgents = false }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        agents = (try? JSONDecoder().decode([AgentSummaryWire].self, from: data)) ?? []
    }
}

// MARK: - Color hex helper

private extension Color {
    init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
