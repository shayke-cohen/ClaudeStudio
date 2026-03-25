import SwiftUI

/// Compact summary card shown at the end of a completed session,
/// displaying cost, tokens, tool calls, duration, and files touched.
struct SessionSummaryCard: View {
    let sessions: [AppState.SessionInfo]
    let toolCalls: [String: [AppState.ToolCallInfo]]
    let duration: TimeInterval?
    @AppStorage(AppSettings.showSessionSummaryKey, store: AppSettings.store) private var showSessionSummary = true
    @State private var isExpanded = false

    private static let fileTools: Set<String> = [
        "edit", "multiedit", "write", "create", "delete",
        "create_file", "delete_file", "rename_file",
    ]

    var body: some View {
        if showSessionSummary {
            summaryContent
        } else {
            legacyBanner
        }
    }

    // MARK: - Legacy AllDoneBanner fallback

    @ViewBuilder
    private var legacyBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("All agents finished")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.green.opacity(0.08))
        .clipShape(Capsule())
        .xrayId("chat.allDoneBanner")
    }

    // MARK: - Summary Content

    @ViewBuilder
    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isExpanded {
                Divider().opacity(0.2)
                detailsSection
            }
        }
        .background(Color.green.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.15), lineWidth: 0.5)
        )
        .xrayId("chat.sessionSummaryCard")
    }

    @ViewBuilder
    private var headerRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13))

                Text("Done")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                // Quick stats in the header
                HStack(spacing: 12) {
                    if totalCost > 0 {
                        statLabel(
                            icon: "dollarsign.circle",
                            value: formatCost(totalCost)
                        )
                    }
                    if totalTokens > 0 {
                        statLabel(
                            icon: "text.word.spacing",
                            value: formatTokens(totalTokens)
                        )
                    }
                    if totalToolCalls > 0 {
                        statLabel(
                            icon: "wrench",
                            value: "\(totalToolCalls)"
                        )
                    }
                    if let duration, duration > 0 {
                        statLabel(
                            icon: "clock",
                            value: formatDuration(duration)
                        )
                    }
                }

                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .xrayId("chat.sessionSummaryCard.header")
    }

    @ViewBuilder
    private func statLabel(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Per-agent breakdown (if multiple agents)
            if sessions.count > 1 {
                ForEach(sessions) { session in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(session.agentName)
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        if session.cost > 0 {
                            Text(formatCost(session.cost))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(session.toolCallCount) tools")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.15)
            }

            // Files touched
            if !filesTouched.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Files touched")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(Array(filesTouched.prefix(10)), id: \.self) { file in
                        HStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange.opacity(0.7))
                            Text(file)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if filesTouched.count > 10 {
                        Text("... and \(filesTouched.count - 10) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Computed Values

    private var totalCost: Double {
        sessions.reduce(0) { $0 + $1.cost }
    }

    private var totalTokens: Int {
        sessions.reduce(0) { $0 + $1.tokenCount }
    }

    private var totalToolCalls: Int {
        sessions.reduce(0) { $0 + $1.toolCallCount }
    }

    private var filesTouched: [String] {
        var files: Set<String> = []
        for (_, calls) in toolCalls {
            for call in calls where Self.fileTools.contains(call.tool.lowercased()) {
                if let data = call.input.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let path = json["file_path"] as? String {
                    let name = (path as NSString).lastPathComponent
                    files.insert(name)
                }
            }
        }
        return files.sorted()
    }

    // MARK: - Formatting

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000)
        }
        return "\(count)"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return "\(min)m \(sec)s"
    }
}
