import SwiftUI
import SwiftData

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Agent.name) private var allAgents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var allGroups: [AgentGroup]
    @Query(sort: \Session.startedAt, order: .reverse) private var recentSessions: [Session]

    var onQuickChat: () -> Void
    var onStartAgent: (Agent) -> Void

    // MARK: - Computed

    private var enabledAgents: [Agent] {
        allAgents.filter(\.isEnabled)
    }

    private var recentAgents: [Agent] {
        var seen = Set<UUID>()
        var result: [Agent] = []
        for session in recentSessions {
            guard let agent = session.agent, agent.isEnabled, !seen.contains(agent.id) else { continue }
            seen.insert(agent.id)
            result.append(agent)
            if result.count >= 6 { break }
        }
        return result
    }

    private var enabledGroups: [AgentGroup] {
        allGroups.filter(\.isEnabled)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                quickActionsGrid
                if !recentAgents.isEmpty {
                    recentAgentsSection
                }
                if !enabledGroups.isEmpty {
                    agentGroupsSection
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .xrayId("welcome.scrollView")
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .xrayId("welcome.heroIcon")
            Text("Welcome to ClaudPeer")
                .font(.largeTitle)
                .fontWeight(.bold)
                .xrayId("welcome.heading")
            Text("Start a conversation with an AI agent, or launch a team of specialists.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .xrayId("welcome.subtitle")
        }
        .padding(.top, 40)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            quickActionCard(
                title: "Quick Chat",
                subtitle: "Freeform, no agent",
                icon: "plus.message",
                shortcut: "\u{21E7}\u{2318}N",
                color: .blue,
                identifier: "welcome.quickAction.quickChat"
            ) {
                onQuickChat()
            }
            quickActionCard(
                title: "New Session",
                subtitle: "Pick an agent and start",
                icon: "plus.bubble",
                shortcut: "\u{2318}N",
                color: .purple,
                identifier: "welcome.quickAction.newSession"
            ) {
                appState.showNewSessionSheet = true
            }
            quickActionCard(
                title: "Browse Agents",
                subtitle: "\(enabledAgents.count) available",
                icon: "cpu",
                shortcut: nil,
                color: .orange,
                identifier: "welcome.quickAction.browseAgents"
            ) {
                appState.showAgentLibrary = true
            }
            quickActionCard(
                title: "Browse Groups",
                subtitle: "\(enabledGroups.count) teams",
                icon: "person.3",
                shortcut: nil,
                color: .teal,
                identifier: "welcome.quickAction.browseGroups"
            ) {
                appState.showGroupLibrary = true
            }
        }
        .frame(maxWidth: 520)
    }

    private func quickActionCard(
        title: String,
        subtitle: String,
        icon: String,
        shortcut: String?,
        color: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .xrayId(identifier)
    }

    // MARK: - Recent Agents

    @ViewBuilder
    private var recentAgentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT AGENTS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .xrayId("welcome.recentAgents")

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
            ], spacing: 12) {
                ForEach(recentAgents) { agent in
                    recentAgentCard(agent)
                }
            }
        }
        .frame(maxWidth: 660)
    }

    private func recentAgentCard(_ agent: Agent) -> some View {
        Button {
            onStartAgent(agent)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: agent.icon)
                    .font(.title3)
                    .foregroundStyle(Color.fromAgentColor(agent.color))
                    .frame(width: 32, height: 32)
                    .background(Color.fromAgentColor(agent.color).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(agent.model)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .xrayId("welcome.recentAgent.\(agent.id.uuidString)")
    }

    // MARK: - Agent Groups

    @ViewBuilder
    private var agentGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AGENT GROUPS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .xrayId("welcome.agentGroups")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(enabledGroups.prefix(6)) { group in
                    welcomeGroupCard(group)
                }
            }
        }
        .frame(maxWidth: 660)
    }

    private func welcomeGroupCard(_ group: AgentGroup) -> some View {
        Button {
            appState.pendingGroupId = group.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(group.icon)
                        .font(.title3)
                    Text(group.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                }
                Text(groupAgentNames(for: group))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .xrayId("welcome.groupCard.\(group.id.uuidString)")
    }

    private func groupAgentNames(for group: AgentGroup) -> String {
        let names = group.agentIds.compactMap { agentId in
            allAgents.first { $0.id == agentId }?.name
        }
        guard !names.isEmpty else { return "No agents" }
        return names.joined(separator: ", ")
    }
}
