import SwiftUI
import SwiftData

struct GroupPickerPopover: View {
    let projectId: UUID?
    let projectDirectory: String
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState

    @Query(sort: \AgentGroup.name) private var allGroups: [AgentGroup]
    @Query(sort: \Agent.name) private var allAgents: [Agent]

    @State private var searchText = ""
    @State private var missionText = ""
    @State private var showMission = false
    @FocusState private var searchFocused: Bool
    @FocusState private var missionFocused: Bool

    private var filteredGroups: [AgentGroup] {
        guard !searchText.isEmpty else { return allGroups }
        return allGroups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if showMission { missionSection }
            groupList
            Divider()
            footer
        }
        .frame(width: 260)
        .background(.background)
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            TextField("Search groups…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.secondary)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MISSION")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.purple)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            TextEditor(text: $missionText)
                .font(.system(size: 12))
                .focused($missionFocused)
                .frame(height: 56)
                .padding(.horizontal, 8)
                .scrollContentBackground(.hidden)
                .background(Color.purple.opacity(0.08))
            Text("Select a group below to start  ·  esc to cancel")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .background(Color.purple.opacity(0.06))
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredGroups) { group in
                    Button { openGroupThread(group) } label: {
                        groupRow(group)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 240)
    }

    private func groupRow(_ group: AgentGroup) -> some View {
        let memberAgents = allAgents.filter { group.agentIds.contains($0.id) }
        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.blue.opacity(0.12))
                Image(systemName: "person.3.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                HStack(spacing: 3) {
                    ForEach(memberAgents.prefix(4)) { agent in
                        Circle()
                            .fill(Color.fromAgentColor(agent.color))
                            .frame(width: 6, height: 6)
                    }
                    Text("\(group.agentIds.count) agents")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
            }
            Spacer()
            Text("↵")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.background.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack {
            Text("Click to start")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            Spacer()
            Button("") { toggleMission() }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
            Text(showMission ? "⌘↵ hide mission" : "⌘↵ add mission")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.background.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func toggleMission() {
        withAnimation(.easeInOut(duration: 0.15)) { showMission.toggle() }
        if showMission { missionFocused = true }
    }

    private func openGroupThread(_ group: AgentGroup) {
        let mission = missionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let convId = appState.startGroupChat(
            group: group,
            projectDirectory: projectDirectory,
            projectId: projectId,
            modelContext: modelContext,
            missionOverride: mission.isEmpty ? nil : mission
        ) else { return }
        windowState.selectedConversationId = convId
        isPresented = false
    }
}
