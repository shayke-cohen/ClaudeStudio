import SwiftUI

struct AgentActivityBar: View {
    let sessions: [Session]
    let sessionActivity: [String: AppState.SessionActivityState]
    var participants: [Participant] = []

    var body: some View {
        let items = sessions.map { session -> AgentActivityItem in
            let key = session.id.uuidString
            let state = sessionActivity[key] ?? .idle
            let participant = participants.first { p in
                if case .agentSession(let sid) = p.type { return sid == session.id }
                return false
            }
            return AgentActivityItem(
                id: session.id,
                name: session.agent?.name ?? "Agent",
                state: state,
                isSilentObserver: participant?.role == .silentObserver,
                isVerified: participant?.isVerified ?? false,
                ownerDisplayName: participant?.ownerDisplayName
            )
        }

        if !items.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(items) { item in
                    agentPill(item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .xrayId("chat.agentActivityBar")
        }
    }

    private func agentPill(_ item: AgentActivityItem) -> some View {
        HStack(spacing: 4) {
            if item.isSilentObserver {
                Image(systemName: "eye")
                    .font(.system(size: 6))
                    .foregroundStyle(.secondary)
            } else {
                ActivityDot(state: item.state)
                    .frame(width: 6, height: 6)
            }

            Text(item.name)
                .font(.caption2)
                .fontWeight(.medium)

            if item.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Verified")
            }

            if !item.isSilentObserver {
                Text(item.state.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let owner = item.ownerDisplayName {
                Text("· by \(owner)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(item.isSilentObserver ? Color.secondary.opacity(0.08) : item.state.displayColor.opacity(0.1))
        .clipShape(Capsule())
        .xrayId("chat.agentPill.\(item.id.uuidString)")
        .accessibilityLabel(item.isSilentObserver
            ? "\(item.name): silent observer"
            : "\(item.name): \(item.state.displayLabel)")
        .help(item.isSilentObserver
            ? "Silent observer — receives all messages, responds only when @mentioned"
            : "")
    }
}

// MARK: - Supporting Types

private struct AgentActivityItem: Identifiable {
    let id: UUID
    let name: String
    let state: AppState.SessionActivityState
    var isSilentObserver: Bool = false
    var isVerified: Bool = false
    var ownerDisplayName: String? = nil
}

struct ActivityDot: View {
    let state: AppState.SessionActivityState
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(state.displayColor)
            .scaleEffect(state.isActive && pulsing ? 1.0 : (state.isActive ? 0.5 : 1.0))
            .opacity(state.isActive && !pulsing ? 0.5 : 1.0)
            .animation(
                state.isActive
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
            .onAppear {
                if state.isActive { pulsing = true }
            }
            .onChange(of: state.isActive) { _, active in
                pulsing = active
            }
            .xrayId("activityDot")
            .accessibilityLabel(state.displayLabel)
    }
}

// Uses FlowLayout from AgentPreviewCard.swift
