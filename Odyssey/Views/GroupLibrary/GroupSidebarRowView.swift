import SwiftUI
import SwiftData

struct GroupSidebarRowView: View {
    let group: AgentGroup
    let conversations: [Conversation]
    var archivedConversations: [Conversation] = []
    let allAgents: [Agent]
    @Binding var isExpanded: Bool
    let onNewChat: () -> Void
    let onNewAutonomousChat: (() -> Void)?
    let onSelectConversation: (Conversation) -> Void
    var onSelectGroup: (() -> Void)?
    var onEdit: (() -> Void)?
    var onRename: ((Conversation) -> Void)?
    var selectedConversationId: UUID?
    var hasActiveSession: Bool = false
    var onDeleteConversation: ((Conversation) -> Void)?
    var projects: [Project] = []
    var onNewSessionInProject: ((Project) -> Void)?
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
                .stableXrayId("sidebar.groupRow.\(group.id.uuidString).chatRow.\(conv.id.uuidString)")
                .accessibilityIdentifier("sidebar.groupThreadRow.\(conv.id.uuidString)")
                .contextMenu {
                    Button("Open Thread") {
                        onSelectConversation(conv)
                    }
                    Divider()
                    Button("Rename\u{2026}") { onRename?(conv) }
                        .accessibilityIdentifier("sidebar.groupRow.\(group.id.uuidString).chatRow.\(conv.id.uuidString).rename")
                    Button("Archive") {
                        conv.isArchived = true
                        conv.isPinned = false
                        try? modelContext.save()
                    }
                    .accessibilityIdentifier("sidebar.groupThreadRow.archive.\(conv.id.uuidString)")
                    Button("Delete\u{2026}", role: .destructive) {
                        onDeleteConversation?(conv)
                    }
                    .accessibilityIdentifier("sidebar.groupThreadRow.delete.\(conv.id.uuidString)")
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
                .accessibilityIdentifier("sidebar.agentShowAllThreads.\(group.id.uuidString)")
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
                        .accessibilityIdentifier("sidebar.groupArchivedThreadRow.\(conv.id.uuidString)")
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
                .accessibilityIdentifier("sidebar.groupArchivedSection.\(group.id.uuidString)")
            }
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(group.icon)
                        .font(.body)
                        .frame(width: 22, height: 22)
                        .background(Color.fromAgentColor(group.color).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.name)
                            .font(.body)
                            .lineLimit(1)
                        let memberNames = allAgents.filter { group.agentIds.contains($0.id) }.map(\.name).joined(separator: " · ")
                        if !memberNames.isEmpty {
                            Text(memberNames)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelectGroup?() }

                Spacer()

                if hasActiveSession {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .stableXrayId("sidebar.groupRow.\(group.id.uuidString).activityDot")
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

                if group.autonomousCapable, let onAuto = onNewAutonomousChat {
                    Button { onAuto() } label: {
                        Image(systemName: "bolt")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Start autonomous mission")
                    .accessibilityLabel("Start autonomous mission for \(group.name)")
                    .stableXrayId("sidebar.groupRow.\(group.id.uuidString).autonomousButton")
                }

                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New group thread with \(group.name)")
                .stableXrayId("sidebar.groupRow.\(group.id.uuidString).newChatButton")
            }
            .stableXrayId("sidebar.groupRow.\(group.id.uuidString)")
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contextMenu {
                Button("Start Chat") { onNewChat() }
                    .accessibilityIdentifier("sidebar.groupContext.startChat.\(group.id.uuidString)")

                Menu("New Thread in Project\u{2026}") {
                    ForEach(projects) { project in
                        Button(project.name) { onNewSessionInProject?(project) }
                    }
                    if projects.isEmpty {
                        Text("No projects").foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("sidebar.groupContext.newThreadInProject.\(group.id.uuidString)")

                Divider()

                Button("View Session History") { onViewSessionHistory?() }
                    .accessibilityIdentifier("sidebar.groupContext.viewHistory.\(group.id.uuidString)")

                Divider()

                Button("Hide from Sidebar") { onHideFromSidebar?() }
                    .accessibilityIdentifier("sidebar.groupContext.hideSidebar.\(group.id.uuidString)")

                Divider()

                Button("Schedule Mission\u{2026}") { onScheduleMission?() }
                    .accessibilityIdentifier("sidebar.groupContext.schedule.\(group.id.uuidString)")

                Divider()

                Button("Edit") { onEdit?() }
                    .accessibilityIdentifier("sidebar.groupContext.edit.\(group.id.uuidString)")
            }
        }
    }
}
