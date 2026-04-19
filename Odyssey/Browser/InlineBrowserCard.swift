import SwiftUI

/// A compact inline card shown in the message stream when an agent browser session starts.
/// Tapping "Expand" opens the full browser panel. Shows a "Closed" state if the session
/// no longer matches `appState.activeBrowserSessionId`.
struct InlineBrowserCard: View {
    let message: ConversationMessage
    @Environment(AppState.self) private var appState

    /// The session ID stored in `message.toolOutput`.
    private var sessionId: String? { message.toolOutput }

    /// True when this card's session is the currently active browser session.
    private var isActive: Bool {
        guard let sid = sessionId else { return false }
        return appState.activeBrowserSessionId == sid
    }

    /// True when the browser panel is open and showing this session.
    private var isPanelOpen: Bool {
        isActive && appState.activeBrowserPanelVisible
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(isActive ? .blue : .secondary)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 2) {
                Text("Browser")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isActive ? .primary : .secondary)
                Text(isActive ? "Agent Canvas" : "Session ended")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isActive {
                Button {
                    appState.activeBrowserPanelVisible = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isPanelOpen
                              ? "arrow.up.left.and.arrow.down.right.square.fill"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12))
                        Text(isPanelOpen ? "Viewing" : "Expand")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(isPanelOpen ? .blue : .blue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inlineBrowser.expandButton")
                .accessibilityLabel(isPanelOpen ? "Browser panel open" : "Expand browser panel")
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                    Text("Closed")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(isActive ? .blue.opacity(0.08) : Color(.quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? .blue.opacity(0.2) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .accessibilityIdentifier("inlineBrowser.card")
    }
}
