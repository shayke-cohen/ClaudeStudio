// OdysseyiOS/Views/ConversationListView.swift
import SwiftUI
import OdysseyCore

/// Lists all conversations from the paired Mac and allows navigation into them.
struct ConversationListView: View {
    @Environment(iOSAppState.self) private var appState
    @State private var searchText = ""
    @State private var showNewConversation = false

    var filteredConversations: [ConversationSummaryWire] {
        if searchText.isEmpty { return appState.conversations }
        return appState.conversations.filter {
            $0.topic.localizedCaseInsensitiveContains(searchText) ||
            $0.lastMessagePreview.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.conversations.isEmpty {
                    VStack(spacing: 8) {
                        ContentUnavailableView(
                            "No Conversations",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Connect to your Mac to see conversations here.")
                        )
                        if let err = appState.lanLoadError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .accessibilityIdentifier("conversationList.emptyState")
                } else {
                    List(filteredConversations) { conversation in
                        NavigationLink {
                            iOSChatView(conversation: conversation)
                        } label: {
                            ConversationRowView(conversation: conversation)
                        }
                        .accessibilityIdentifier("conversationList.row.\(conversation.id)")
                    }
                    .accessibilityIdentifier("conversationList.list")
                    .searchable(text: $searchText, prompt: "Search conversations")
                    .accessibilityIdentifier("conversationList.search")
                    .refreshable { await appState.loadConversations() }
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await appState.loadConversations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("conversationList.refreshButton")
                    .accessibilityLabel("Refresh conversations")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showNewConversation = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("conversationList.newButton")
                    .accessibilityLabel("New conversation")
                }
            }
        }
        .task {
            await appState.loadConversations()
        }
        .sheet(isPresented: $showNewConversation) {
            iOSAgentListView()
                .environment(appState)
        }
    }
}

// MARK: - Row

private struct ConversationRowView: View {
    let conversation: ConversationSummaryWire

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.topic)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if conversation.unread {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Unread")
                }
            }
            Text(conversation.lastMessagePreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let project = conversation.projectName {
                Text(project)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}
