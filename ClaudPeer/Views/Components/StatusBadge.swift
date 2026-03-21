import SwiftUI

struct StatusBadge: View {
    let status: String
    let color: Color

    init(sessionStatus: SessionStatus) {
        switch sessionStatus {
        case .active:
            self.status = "Active"
            self.color = .green
        case .paused:
            self.status = "Paused"
            self.color = .yellow
        case .completed:
            self.status = "Done"
            self.color = .gray
        case .failed:
            self.status = "Failed"
            self.color = .red
        }
    }

    init(conversationStatus: ConversationStatus) {
        switch conversationStatus {
        case .active:
            self.status = "Active"
            self.color = .green
        case .closed:
            self.status = "Closed"
            self.color = .gray
        }
    }

    init(status: String, color: Color) {
        self.status = status
        self.color = color
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(status)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
        .accessibilityIdentifier("statusBadge.\(status.lowercased())")
        .accessibilityLabel("Status: \(status)")
    }
}
