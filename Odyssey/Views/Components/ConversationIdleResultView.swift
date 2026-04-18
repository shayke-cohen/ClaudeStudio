import SwiftUI

struct ConversationIdleResultView: View {
    let conversationId: String
    @Environment(AppState.self) var appState

    private var idleResult: ConversationIdleResult? {
        appState.idleResults[conversationId]
    }

    private var isEvaluating: Bool {
        appState.evaluatingConversations.contains(conversationId)
    }

    var body: some View {
        if let result = idleResult {
            pill(
                icon: result.status.icon,
                label: result.status.label + (result.reason.isEmpty ? "" : " — \(result.reason)"),
                color: result.status.color
            )
        } else if isEvaluating {
            pill(icon: "ellipsis.circle", label: "Evaluating…", color: .secondary)
        }
    }

    @ViewBuilder
    private func pill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
        .xrayId("chat.idleResultView")
    }
}

extension ConversationIdleResult.Status {
    var icon: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        case .needsMore: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .complete: return "Goal achieved"
        case .needsMore: return "Needs more work"
        case .failed: return "Failed"
        }
    }

    var color: Color {
        switch self {
        case .complete: return .green
        case .needsMore: return .yellow
        case .failed: return .red
        }
    }
}
