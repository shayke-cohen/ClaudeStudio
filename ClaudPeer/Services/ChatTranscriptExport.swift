import Foundation
import WebKit

// MARK: - Snapshot

struct ChatTranscriptStreamingAppendix: Sendable, Equatable {
    var text: String
    var thinking: String
    var displayName: String

    var isEmpty: Bool { text.isEmpty && thinking.isEmpty }
}

struct ChatTranscriptSnapshot: Sendable {
    struct Row: Sendable {
        enum Kind: Sendable {
            case chat(sender: String, timestampISO: String, text: String, thinking: String?, attachmentNames: [String])
            case toolCall(sender: String, timestampISO: String, toolName: String?, input: String?)
            case toolResult(sender: String, timestampISO: String, toolName: String?, output: String?)
            case labeled(kindLabel: String, sender: String, timestampISO: String, text: String)
        }

        var kind: Kind
    }

    var title: String
    var startedAtISO: String?
    var rows: [Row]
    var streamingAppendix: ChatTranscriptStreamingAppendix?
}

enum ChatTranscriptExport {

    private static func isoTimestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func snapshot(
        conversation: Conversation,
        messages: [ConversationMessage],
        participants: [Participant],
        streamingAppendix: ChatTranscriptStreamingAppendix?
    ) -> ChatTranscriptSnapshot {
        let title = conversation.topic?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Chat"
        let started = isoTimestamp(conversation.startedAt)

        func senderName(for message: ConversationMessage) -> String {
            guard let pid = message.senderParticipantId else { return "Unknown" }
            return participants.first { $0.id == pid }?.displayName ?? "Unknown"
        }

        var rows: [ChatTranscriptSnapshot.Row] = []
        rows.reserveCapacity(messages.count)

        for message in messages {
            let ts = isoTimestamp(message.timestamp)
            let sender = senderName(for: message)
            switch message.type {
            case .chat:
                let names = message.attachments.map(\.fileName)
                rows.append(ChatTranscriptSnapshot.Row(kind: .chat(
                    sender: sender,
                    timestampISO: ts,
                    text: message.text,
                    thinking: message.thinkingText.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty },
                    attachmentNames: names
                )))
            case .toolCall:
                rows.append(ChatTranscriptSnapshot.Row(kind: .toolCall(
                    sender: sender,
                    timestampISO: ts,
                    toolName: message.toolName,
                    input: message.toolInput
                )))
            case .toolResult:
                rows.append(ChatTranscriptSnapshot.Row(kind: .toolResult(
                    sender: sender,
                    timestampISO: ts,
                    toolName: message.toolName,
                    output: message.toolOutput
                )))
            case .system:
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    kindLabel: "System",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text
                )))
            case .delegation:
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    kindLabel: "Delegation",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text
                )))
            case .blackboardUpdate:
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    kindLabel: "Blackboard",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text
                )))
            case .question:
                let answerText = message.toolInput ?? ""
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    kindLabel: "Question",
                    sender: sender,
                    timestampISO: ts,
                    text: "\(message.text)\nAnswer: \(answerText)"
                )))
            case .richContent:
                let format = message.toolName ?? "html"
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    kindLabel: "Rich Content (\(format))",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text
                )))
            }
        }

        let appendix = streamingAppendix.flatMap { $0.isEmpty ? nil : $0 }
        return ChatTranscriptSnapshot(title: title, startedAtISO: started, rows: rows, streamingAppendix: appendix)
    }

    static func markdown(_ snapshot: ChatTranscriptSnapshot) -> String {
        var parts: [String] = []
        parts.append("# \(snapshot.title)")
        if let started = snapshot.startedAtISO {
            parts.append("")
            parts.append("_Started: \(started)_")
        }
        parts.append("")

        if snapshot.rows.isEmpty, snapshot.streamingAppendix == nil {
            parts.append("_No messages._")
            return parts.joined(separator: "\n")
        }

        for row in snapshot.rows {
            parts.append("---")
            parts.append("")
            parts.append(contentsOf: markdownLines(for: row))
            parts.append("")
        }

        if let app = snapshot.streamingAppendix {
            parts.append("---")
            parts.append("")
            parts.append("## In progress (not yet saved)")
            parts.append("")
            parts.append("**\(app.displayName)**")
            parts.append("")
            if !app.thinking.isEmpty {
                parts.append("### Thinking")
                parts.append("")
                parts.append(indentedBlock(app.thinking))
                parts.append("")
            }
            if !app.text.isEmpty {
                parts.append(indentedBlock(app.text))
                parts.append("")
            }
        }

        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func markdownLines(for row: ChatTranscriptSnapshot.Row) -> [String] {
        switch row.kind {
        case .chat(let sender, let ts, let text, let thinking, let attachments):
            var lines: [String] = []
            lines.append("## \(sender) · \(ts)")
            if let thinking, !thinking.isEmpty {
                lines.append("")
                lines.append("### Thinking")
                lines.append("")
                lines.append(indentedBlock(thinking))
            }
            if !attachments.isEmpty {
                lines.append("")
                lines.append("_Attachments: \(attachments.joined(separator: ", "))_")
            }
            if !text.isEmpty {
                lines.append("")
                lines.append(sanitizeMarkdownBody(text))
            }
            return lines
        case .toolCall(let sender, let ts, let toolName, let input):
            var lines: [String] = [
                "## Tool call · \(sender) · \(ts)",
                ""
            ]
            if let name = toolName, !name.isEmpty {
                lines.append("**Tool:** `\(name)`")
                lines.append("")
            }
            if let input, !input.isEmpty {
                lines.append("```json")
                lines.append(input)
                lines.append("```")
            }
            return lines
        case .toolResult(let sender, let ts, let toolName, let output):
            var lines: [String] = [
                "## Tool result · \(sender) · \(ts)",
                ""
            ]
            if let name = toolName, !name.isEmpty {
                lines.append("**Tool:** `\(name)`")
                lines.append("")
            }
            if let output, !output.isEmpty {
                lines.append("```")
                lines.append(output)
                lines.append("```")
            }
            return lines
        case .labeled(let label, let sender, let ts, let text):
            var lines: [String] = [
                "## \(label) · \(sender) · \(ts)",
                ""
            ]
            if !text.isEmpty {
                lines.append(sanitizeMarkdownBody(text))
            }
            return lines
        }
    }

    /// Avoid breaking markdown structure if user text contains triple backticks.
    private static func sanitizeMarkdownBody(_ text: String) -> String {
        text.replacingOccurrences(of: "```", with: "``\\`")
    }

    private static func indentedBlock(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in "    " + line }
            .joined(separator: "\n")
    }

    static func html(_ snapshot: ChatTranscriptSnapshot) -> String {
        var body = ""
        body += "<h1>\(escapeHTML(snapshot.title))</h1>\n"
        if let started = snapshot.startedAtISO {
            body += "<p class=\"meta\">Started: \(escapeHTML(started))</p>\n"
        }

        if snapshot.rows.isEmpty, snapshot.streamingAppendix == nil {
            body += "<p class=\"empty\">No messages.</p>\n"
        } else {
            for row in snapshot.rows {
                body += "<hr/>\n"
                body += htmlBlock(for: row)
            }
            if let app = snapshot.streamingAppendix {
                body += "<hr/>\n"
                body += "<h2>In progress (not yet saved)</h2>\n"
                body += "<p class=\"sender\"><strong>\(escapeHTML(app.displayName))</strong></p>\n"
                if !app.thinking.isEmpty {
                    body += "<h3>Thinking</h3>\n"
                    body += "<pre class=\"thinking\">\(escapeHTML(app.thinking))</pre>\n"
                }
                if !app.text.isEmpty {
                    body += "<div class=\"chat\">\(htmlParagraphs(app.text))</div>\n"
                }
            }
        }

        return htmlDocument(pageTitle: snapshot.title, body: body)
    }

    private static func htmlBlock(for row: ChatTranscriptSnapshot.Row) -> String {
        switch row.kind {
        case .chat(let sender, let ts, let text, let thinking, let attachments):
            var s = ""
            s += "<h2>\(escapeHTML(sender)) · \(escapeHTML(ts))</h2>\n"
            if let thinking, !thinking.isEmpty {
                s += "<h3>Thinking</h3>\n"
                s += "<pre class=\"thinking\">\(escapeHTML(thinking))</pre>\n"
            }
            if !attachments.isEmpty {
                s += "<p class=\"attachments\"><em>Attachments: \(escapeHTML(attachments.joined(separator: ", ")))</em></p>\n"
            }
            if !text.isEmpty {
                s += "<div class=\"chat\">\(htmlParagraphs(text))</div>\n"
            }
            return s
        case .toolCall(let sender, let ts, let toolName, let input):
            var s = "<h2>Tool call · \(escapeHTML(sender)) · \(escapeHTML(ts))</h2>\n"
            if let name = toolName, !name.isEmpty {
                s += "<p><strong>Tool:</strong> <code>\(escapeHTML(name))</code></p>\n"
            }
            if let input, !input.isEmpty {
                s += "<pre><code>\(escapeHTML(input))</code></pre>\n"
            }
            return s
        case .toolResult(let sender, let ts, let toolName, let output):
            var s = "<h2>Tool result · \(escapeHTML(sender)) · \(escapeHTML(ts))</h2>\n"
            if let name = toolName, !name.isEmpty {
                s += "<p><strong>Tool:</strong> <code>\(escapeHTML(name))</code></p>\n"
            }
            if let output, !output.isEmpty {
                s += "<pre><code>\(escapeHTML(output))</code></pre>\n"
            }
            return s
        case .labeled(let label, let sender, let ts, let text):
            var s = "<h2>\(escapeHTML(label)) · \(escapeHTML(sender)) · \(escapeHTML(ts))</h2>\n"
            if !text.isEmpty {
                s += "<div class=\"chat\">\(htmlParagraphs(text))</div>\n"
            }
            return s
        }
    }

    private static func htmlParagraphs(_ text: String) -> String {
        text
            .split(separator: "\n\n", omittingEmptySubsequences: false)
            .map { para in "<p>\(escapeHTML(String(para)).replacingOccurrences(of: "\n", with: "<br/>"))</p>" }
            .joined(separator: "\n")
    }

    private static func escapeHTML(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.utf8.count)
        for ch in string {
            switch ch {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            case "\"": result.append("&quot;")
            case "'": result.append("&#39;")
            default: result.append(ch)
            }
        }
        return result
    }

    private static func htmlDocument(pageTitle: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>\(escapeHTML(pageTitle))</title>
        <style>
          body { font-family: -apple-system, system-ui, sans-serif; line-height: 1.45; max-width: 52rem; margin: 2rem auto; padding: 0 1.25rem; color: #111; }
          .meta, .empty { color: #555; }
          pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.88em; }
          pre { white-space: pre-wrap; word-break: break-word; background: #f4f4f5; padding: 0.75rem 1rem; border-radius: 6px; overflow-x: auto; }
          pre.thinking { background: #f0eef8; }
          hr { border: none; border-top: 1px solid #ddd; margin: 1.5rem 0; }
          h1 { font-size: 1.5rem; }
          h2 { font-size: 1.15rem; margin-top: 0.5rem; }
          h3 { font-size: 1rem; color: #444; }
          .attachments { font-size: 0.9rem; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func suggestedBaseFileName(for snapshot: ChatTranscriptSnapshot) -> String {
        var s = snapshot.title
        for old in ["/", "\\", "<", ">", "|", "\"", "?", "*", ":", "\n", "\r", "\t"] {
            s = s.replacingOccurrences(of: old, with: "-")
        }
        while s.contains("--") {
            s = s.replacingOccurrences(of: "--", with: "-")
        }
        let base = s.trimmingCharacters(in: CharacterSet(charactersIn: "- ").union(.whitespacesAndNewlines))
        let safeBase = base.isEmpty ? "chat" : base
        let day = Self.dayStamp()
        return "\(safeBase)-\(day)"
    }

    private static func dayStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - PDF (WKWebView)

@MainActor
final class ChatTranscriptPDFRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completion: ((Result<Data, Error>) -> Void)?
    private var loadedHTML: String?

    func renderPDF(html: String) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            self.loadedHTML = html
            self.completion = { result in
                switch result {
                case .success(let data): cont.resume(returning: data)
                case .failure(let err): cont.resume(throwing: err)
                }
            }

            let config = WKWebViewConfiguration()
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), configuration: config)
            wv.navigationDelegate = self
            self.webView = wv
            wv.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let pdfConfig = WKPDFConfiguration()
        webView.createPDF(configuration: pdfConfig) { [weak self] result in
            guard let self else { return }
            self.webView = nil
            self.completion?(result)
            self.completion = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishFailure(error)
    }

    private func finishFailure(_ error: Error) {
        webView = nil
        completion?(.failure(error))
        completion = nil
    }
}
