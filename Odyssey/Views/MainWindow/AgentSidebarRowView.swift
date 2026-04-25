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
    var projects: [Project] = []
    var onNewSessionInProject: ((Project) -> Void)?
    var onTogglePin: (() -> Void)?
    var onHideFromSidebar: (() -> Void)?
    var onScheduleMission: (() -> Void)?
    var onViewSessionHistory: (() -> Void)?
    var onCloseConversation: ((Conversation) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var showAllConversations = false
    var isArchivedExpanded: Binding<Bool>
    @State private var isHeaderHovered = false

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
                    threadRowLabel(conv, isConvSelected: isConvSelected)
                }
                .buttonStyle(.plain)
                .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).chatRow.\(conv.id.uuidString)")
                .accessibilityIdentifier("sidebar.agentThreadRow.\(conv.id.uuidString)")
                .accessibilityLabel("Open chat \(conv.topic ?? "Untitled")")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { onDeleteConversation?(conv) } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete")
                    Button {
                        conv.isArchived = true
                        conv.isPinned = false
                        try? modelContext.save()
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .help("Archive")
                    .tint(.indigo)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        conv.isPinned.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: conv.isPinned ? "pin.slash" : "pin")
                    }
                    .help(conv.isPinned ? "Unpin" : "Pin")
                    .tint(.yellow)
                }
                .contextMenu {
                    Button("Open Thread") { onSelectConversation(conv) }
                    Divider()
                    Button("Rename\u{2026}") { onRename?(conv) }
                    Button {
                        conv.isPinned.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(conv.isPinned ? "Unpin" : "Pin", systemImage: conv.isPinned ? "pin.slash" : "pin")
                    }
                    Button {
                        conv.isUnread.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(conv.isUnread ? "Mark as Read" : "Mark as Unread",
                              systemImage: conv.isUnread ? "envelope.open" : "envelope.badge")
                    }
                    if conv.status == .active {
                        Button("Close Session") { onCloseConversation?(conv) }
                    }
                    Divider()
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
                DisclosureGroup(isExpanded: isArchivedExpanded) {
                    ForEach(archivedConversations) { conv in
                        let isConvSelected = selectedConversationId == conv.id
                        Button {
                            onSelectConversation(conv)
                        } label: {
                            HStack(spacing: 6) {
                                Text(conv.topic ?? "Untitled")
                                    .font(.caption)
                                    .foregroundStyle(isConvSelected ? .primary : .tertiary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(conv.startedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.quaternary)
                                    .fixedSize()
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(isConvSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebar.agentArchivedThreadRow.\(conv.id.uuidString)")
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                conv.isArchived = false
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "tray.and.arrow.up")
                            }
                            .help("Unarchive")
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { onDeleteConversation?(conv) } label: {
                                Image(systemName: "trash")
                            }
                            .help("Delete")
                        }
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
            let tint = Color.fromAgentColor(agent.color)
            HStack(spacing: 8) {
                Button {
                    onSelectAgent?()
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [tint.opacity(isSelected ? 0.22 : 0.18), tint.opacity(isSelected ? 0.10 : 0.08)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(tint.opacity(isSelected ? 0.28 : 0.16), lineWidth: 1)
                            Image(systemName: agent.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(tint)
                        }
                        .frame(width: 28, height: 28)
                        Text(agent.name)
                            .font(isSelected ? .headline.weight(.semibold) : .headline.weight(.medium))
                            .lineLimit(1)
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint.opacity(isSelected ? 0.9 : 0.7))
                }
                if isHeaderHovered {
                    Menu {
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
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).moreMenu")

                    Button {
                        onNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .stableXrayId("sidebar.agentRow.\(agent.id.uuidString).newChatButton")
                    .accessibilityLabel("New chat for \(agent.name)")
                }
            }
            .stableXrayId("sidebar.agentRow.\(agent.id.uuidString)")
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                        ? AnyShapeStyle(LinearGradient(
                            colors: [tint.opacity(0.18), tint.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color.primary.opacity(0.04))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.22) : Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: isSelected ? tint.opacity(0.10) : .clear, radius: 8, y: 4)
            .onHover { hovering in isHeaderHovered = hovering }
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
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { onNewChat() } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New Session")
            .tint(Color.fromAgentColor(agent.color))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { onHideFromSidebar?() } label: {
                Image(systemName: "eye.slash")
            }
            .help("Hide")
            .tint(.gray)
            Button { onTogglePin?() } label: {
                Image(systemName: isPinned ? "pin.slash" : "pin")
            }
            .help(isPinned ? "Unpin" : "Pin")
            .tint(.yellow)
            .accessibilityIdentifier("sidebar.agentRow.swipePin.\(agent.id.uuidString)")
        }
    }

    @ViewBuilder
    private func threadRowLabel(
        _ conv: Conversation,
        isConvSelected: Bool
    ) -> some View {
        HStack(spacing: 6) {
            if conv.isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            }

            Text(conv.topic ?? "Untitled")
                .font(conv.isUnread ? .callout.bold() : .callout)
                .foregroundStyle(isConvSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ThreadActivityIndicator(conversation: conv)

            Text(conv.startedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isConvSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Isolated Activity Indicator

/// Leaf view that reads `appState.conversationActivity(for:)` in its own body so
/// only this indicator re-renders when session activity changes — not the parent
/// ForEach or the containing sidebar row.
struct ThreadActivityIndicator: View {
    @Environment(AppState.self) private var appState
    let conversation: Conversation

    var body: some View {
        let summary = appState.conversationActivity(for: conversation)
        SidebarActivityIndicator(summary: summary, conversationStatus: conversation.status)
    }
}
