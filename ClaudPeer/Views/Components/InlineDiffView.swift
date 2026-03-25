import SwiftUI

/// Renders a file edit as a colored inline diff with red (removed) / green (added) lines.
struct InlineDiffView: View {
    let filePath: String
    let oldText: String
    let newText: String
    @State private var isExpanded = true
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().opacity(0.3)
                diffContent
            }
        }
        .background(Color(.textBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .xrayId("inlineDiff.container")
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.gearshape.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)

                Text(fileName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                HStack(spacing: 8) {
                    if !removedCount.isEmpty {
                        Text(removedCount)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    if !addedCount.isEmpty {
                        Text(addedCount)
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                copyButton

                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .xrayId("inlineDiff.header")
    }

    @ViewBuilder
    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(newText, forType: .string)
            withAnimation { isCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { isCopied = false }
            }
        } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(isCopied ? .green : .secondary)
        }
        .buttonStyle(.borderless)
        .help("Copy new content")
        .xrayId("inlineDiff.copyButton")
    }

    // MARK: - Diff Content

    @ViewBuilder
    private var diffContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                    diffLineView(line)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 400)
        .xrayId("inlineDiff.content")
    }

    @ViewBuilder
    private func diffLineView(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            Text(line.prefix)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(line.color)
                .frame(width: 14, alignment: .center)

            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(line.color)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.background)
    }

    // MARK: - Diff Computation

    private struct DiffLine {
        let prefix: String
        let text: String
        let kind: Kind

        enum Kind { case context, added, removed }

        var color: Color {
            switch kind {
            case .context: .primary
            case .added: .green
            case .removed: .red
            }
        }

        var background: Color {
            switch kind {
            case .context: .clear
            case .added: Color.green.opacity(0.08)
            case .removed: Color.red.opacity(0.08)
            }
        }
    }

    private var diffLines: [DiffLine] {
        let oldLines = oldText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Simple line-by-line diff using LCS
        let lcs = longestCommonSubsequence(oldLines, newLines)
        var result: [DiffLine] = []
        var oi = 0, ni = 0, li = 0

        while oi < oldLines.count || ni < newLines.count {
            if li < lcs.count, oi < oldLines.count, ni < newLines.count, oldLines[oi] == lcs[li], newLines[ni] == lcs[li] {
                result.append(DiffLine(prefix: " ", text: oldLines[oi], kind: .context))
                oi += 1; ni += 1; li += 1
            } else if oi < oldLines.count && (li >= lcs.count || oldLines[oi] != lcs[li]) {
                result.append(DiffLine(prefix: "-", text: oldLines[oi], kind: .removed))
                oi += 1
            } else if ni < newLines.count {
                result.append(DiffLine(prefix: "+", text: newLines[ni], kind: .added))
                ni += 1
            }
        }

        return result
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        guard m > 0, n > 0 else { return [] }

        // Cap size to avoid excessive memory for very large diffs
        if m > 500 || n > 500 {
            // Fallback: show all old as removed, all new as added
            return []
        }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] + 1 : max(dp[i - 1][j], dp[i][j - 1])
            }
        }

        var result: [String] = []
        var i = m, j = n
        while i > 0, j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1; j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }

    // MARK: - Helpers

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    private var removedCount: String {
        let count = diffLines.filter { $0.kind == .removed }.count
        return count > 0 ? "-\(count)" : ""
    }

    private var addedCount: String {
        let count = diffLines.filter { $0.kind == .added }.count
        return count > 0 ? "+\(count)" : ""
    }
}

// MARK: - Helpers for extracting diff data from tool call messages

extension InlineDiffView {
    /// Try to create an InlineDiffView from a tool call ConversationMessage (Edit tool).
    static func fromEditToolCall(_ message: ConversationMessage) -> InlineDiffView? {
        guard let input = message.toolInput,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filePath = json["file_path"] as? String,
              let oldString = json["old_string"] as? String,
              let newString = json["new_string"] as? String else {
            return nil
        }
        return InlineDiffView(filePath: filePath, oldText: oldString, newText: newString)
    }
}
