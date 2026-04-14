// OdysseyiOS/Views/iOSChatView.swift
import SwiftUI
import OdysseyCore

/// Chat view for a single conversation. Streams tokens and shows message history.
struct iOSChatView: View {
    @Environment(iOSAppState.self) private var appState
    let conversation: ConversationSummaryWire

    @State private var messages: [MessageWire] = []
    @State private var inputText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    /// Streaming buffer for the active session.
    var streamingBuffer: String? {
        appState.streamingBuffers[conversation.id]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                        // Streaming indicator
                        if let buffer = streamingBuffer, !buffer.isEmpty {
                            StreamingBubbleView(text: buffer)
                                .id("streaming")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .accessibilityIdentifier("chat.messageList")
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: streamingBuffer) { _, _ in
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("chat.errorLabel")
            }

            Divider()

            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .accessibilityIdentifier("chat.inputField")
                    .onSubmit {
                        // Shift+Return adds newline; Return sends (handled by button)
                    }

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: isSending ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? .blue : .gray)
                }
                .disabled(!canSend)
                .accessibilityIdentifier("chat.sendButton")
                .accessibilityLabel(isSending ? "Stop" : "Send message")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(conversation.topic)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            messages = await appState.loadMessages(for: conversation.id)
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await appState.send(text, to: conversation.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Message bubble

private struct MessageBubbleView: View {
    let message: MessageWire

    var isUser: Bool {
        message.type == "chat" && message.senderParticipantId?.hasPrefix("user") == true
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.text)
                .padding(10)
                .background(isUser ? Color.blue : Color(.secondarySystemBackground))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 40) }
        }
        .accessibilityIdentifier("chat.message.\(message.id)")
    }
}

// MARK: - Streaming bubble

private struct StreamingBubbleView: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                )
            Spacer(minLength: 40)
        }
        .accessibilityIdentifier("chat.streamingBubble")
    }
}
