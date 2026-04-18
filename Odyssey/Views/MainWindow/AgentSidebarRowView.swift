import SwiftUI
import SwiftData

struct AgentSidebarRowView: View {
    let agent: Agent
    let conversations: [Conversation]
    var archivedConversations: [Conversation] = []
    @Binding var isExpanded: Bool
    let onNewChat: () -> Void
    let onSelectConversation: (Conversation) -> Void
    var onSelectAgent: (() -> Void)?
    var onRename: ((Conversation) -> Void)?
    var selectedConversationId: UUID?
    var hasActiveSession: Bool = false
    var onDeleteConversation: ((Conversation) -> Void)?
    var isPinned: Bool = false
    // Agent-level context menu actions (applied to label only)
    var projects: [Project] = []
    var onNewSessionInProject: ((Project) -> Void)?
    var onTogglePin: (() -> Void)?
    var onHideFromSidebar: (() -> Void)?
    var onScheduleMission: (() -> Void)?
    var onViewSessionHistory: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var showAllConversations = false
    @State private var isArchivedExpanded = false

    private var isSelected: Bool {
        guard let selected = selectedConversationId else { return false }
        return conversations.contains { $0.id == selected }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let displayed = showAllConversations ? conversations : Array(conversations.prefix(10))
            ForEach(displayed) { conv in
                let isConvSelected = selectedConversationId == conv.id
                Button {
                    onSelectConversation(conv)
                } label: {
                    HStack(spacing: 6) {
                        if conv.isUnread {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                        }
                        Image(systemName: "bubble.left")
                            .font(.caption2)
                            .foregroundStyle(isConvSelected ? Color.accentColor.opacity(1) : Color.secondary.opacity(0.5))
                        Text(conv.topic ?? "Untitled")
                            .font(conv.isUnread ? .caption.bold() : .caption)
                            .foregroundStyle(isConvSelected ? Color.primary : .primary)
                            .lineLimit(1)
                        Spacer()
                        Text(conv.startedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(isConvSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).chatRow.\(conv.id.uuidString)")
                .accessibilityIdentifier("sidebar.agentThreadRow.\(conv.id.uuidString)")
                .accessibilityLabel("Open chat \(conv.topic ?? "Untitled")")
                .contextMenu {
                    Button("Open Thread") { onSelectConversation(conv) }
                    Divider()
                    Button("Rename\u{2026}") { onRename?(conv) }
                    Button("Archive") {
                        conv.isArchived = true
                        conv.isPinned = false
                        try? modelContext.save()
                    }
                    .accessibilityIdentifier("sidebar.agentThreadRow.archive.\(conv.id.uuidString)")
                    Button("Delete\u{2026}", role: .destructive) { onDeleteConversation?(conv) }
                    .accessibilityIdentifier("sidebar.agentThreadRow.delete.\(conv.id.uuidString)")
                }
            }

            if !showAllConversations && conversations.count > 10 {
                Button("Show all \(conversations.count) threads →") {
                    showAllConversations = true
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .accessibilityIdentifier("sidebar.agentShowAllThreads.\(agent.id.uuidString)")
            }

            if !archivedConversations.isEmpty {
                DisclosureGroup(isExpanded: $isArchivedExpanded) {
                    ForEach(archivedConversations) { conv in
                        let isConvSelected = selectedConversationId == conv.id
                        Button {
                            onSelectConversation(conv)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "archivebox")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(conv.topic ?? "Untitled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(conv.startedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(isConvSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebar.agentArchivedThreadRow.\(conv.id.uuidString)")
                        .contextMenu {
                            Button("Open Thread") { onSelectConversation(conv) }
                            Divider()
                            Button("Unarchive") {
                                conv.isArchived = false
                                try? modelContext.save()
                            }
                            Button("Delete\u{2026}", role: .destructive) { onDeleteConversation?(conv) }
                        }
                    }
                } label: {
                    Text("Archived (\(archivedConversations.count))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 6)
                }
                .accessibilityIdentifier("sidebar.agentArchivedSection.\(agent.id.uuidString)")
            }

        } label: {
            HStack {
                Button {
                    onSelectAgent?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: agent.icon)
                            .foregroundStyle(Color.fromAgentColor(agent.color))
                        Text(agent.name)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).selectButton")
                .accessibilityLabel("Open agent \(agent.name)")
                Spacer()
                if hasActiveSession {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).activityDot")
                }
                if !conversations.isEmpty {
                    Text("\(conversations.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).newChatButton")
                .accessibilityLabel("New chat for \(agent.name)")
            }
            .stableXrayId("sidebar.agentRow.\(agent.id.uuidString)")
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contextMenu {
                Button("New Session") { onNewChat() }
                    .accessibilityIdentifier("sidebar.agentRow.newSession.\(agent.id.uuidString)")

                Menu("New Thread in Project\u{2026}") {
                    ForEach(projects) { project in
                        Button(project.name) { onNewSessionInProject?(project) }
                    }
                    if projects.isEmpty {
                        Text("No projects").foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("sidebar.agentRow.newThreadInProject.\(agent.id.uuidString)")

                Divider()

                Button("View Session History") { onViewSessionHistory?() }
                    .accessibilityIdentifier("sidebar.agentRow.viewHistory.\(agent.id.uuidString)")

                Divider()

                Button(isPinned ? "Unpin from Sidebar" : "Pin to Sidebar") { onTogglePin?() }
                    .accessibilityIdentifier("sidebar.agentRow.togglePin.\(agent.id.uuidString)")

                Button("Hide from Sidebar") { onHideFromSidebar?() }
                    .accessibilityIdentifier("sidebar.agentRow.hideSidebar.\(agent.id.uuidString)")

                Divider()

                Button("Schedule Mission\u{2026}") { onScheduleMission?() }
                    .accessibilityIdentifier("sidebar.agentRow.schedule.\(agent.id.uuidString)")
            }
        }
    }
}
