import Foundation
import WebKit
import AppKit

// MARK: - Snapshot

struct ChatTranscriptStreamingAppendix: Sendable, Equatable {
    var text: String
    var thinking: String
    var displayName: String
    var iconName: String?
    var colorName: String?

    init(
        text: String,
        thinking: String,
        displayName: String,
        iconName: String? = nil,
        colorName: String? = nil
    ) {
        self.text = text
        self.thinking = thinking
        self.displayName = displayName
        self.iconName = iconName
        self.colorName = colorName
    }

    var isEmpty: Bool { text.isEmpty && thinking.isEmpty }
}

struct ChatTranscriptExportTheme: Sendable, Equatable {
    enum Appearance: String, Sendable, Equatable {
        case light
        case dark
    }

    var appearance: Appearance
    var textScale: Double

    static let `default` = Self(appearance: .light, textScale: 1.0)
}

struct ChatTranscriptSenderPresentation: Sendable, Equatable {
    enum Role: String, Sendable, Equatable {
        case user
        case agent
        case system
    }

    var displayName: String
    var role: Role
    var iconName: String?
    var colorName: String?
}

struct ChatTranscriptAttachmentSnapshot: Sendable, Equatable {
    var fileName: String
    var mediaType: String
    var fileSize: Int
    var localFilePath: String?

    var isImage: Bool {
        mediaType.hasPrefix("image/")
    }

    var iconName: String {
        switch mediaType {
        case "text/plain", "text/markdown": return "doc.text"
        case "application/pdf": return "doc.richtext"
        default: return isImage ? "photo" : "doc"
        }
    }

    var formattedSize: String {
        if fileSize < 1024 { return "\(fileSize) B" }
        let kb = Double(fileSize) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024.0)
    }
}

struct ChatTranscriptSnapshot: Sendable {
    struct Row: Sendable {
        enum VisualCategory: String, Sendable {
            case chat
            case toolCall
            case toolResult
            case system
            case peerMessage
            case delegation
            case blackboard
            case task
            case workspace
            case agentInvite
            case question
            case richContent
            case streaming

            var label: String {
                switch self {
                case .chat: return "Chat"
                case .toolCall: return "Tool Call"
                case .toolResult: return "Tool Result"
                case .system: return "System"
                case .peerMessage: return "Peer Message"
                case .delegation: return "Delegation"
                case .blackboard: return "Blackboard"
                case .task: return "Task"
                case .workspace: return "Workspace"
                case .agentInvite: return "Agent Invite"
                case .question: return "Question"
                case .richContent: return "Rich Content"
                case .streaming: return "In Progress"
                }
            }

            var iconName: String? {
                switch self {
                case .chat: return nil
                case .toolCall: return "wrench.fill"
                case .toolResult: return "checkmark.circle.fill"
                case .system: return nil
                case .peerMessage: return "bubble.left.and.bubble.right.fill"
                case .delegation: return "arrow.right.circle.fill"
                case .blackboard: return "square.grid.2x2.fill"
                case .task: return "checklist"
                case .workspace: return "folder.fill"
                case .agentInvite: return "person.badge.plus"
                case .question: return "questionmark.circle.fill"
                case .richContent: return "sparkles.rectangle.stack"
                case .streaming: return "ellipsis.message.fill"
                }
            }

            var colorName: String? {
                switch self {
                case .chat: return nil
                case .toolCall: return "blue"
                case .toolResult: return "green"
                case .system: return nil
                case .peerMessage: return "blue"
                case .delegation: return "orange"
                case .blackboard: return "teal"
                case .task: return "purple"
                case .workspace: return "indigo"
                case .agentInvite: return "green"
                case .question: return "blue"
                case .richContent: return "purple"
                case .streaming: return "indigo"
                }
            }
        }

        enum Kind: Sendable {
            case chat(
                sender: ChatTranscriptSenderPresentation,
                timestampISO: String,
                text: String,
                thinking: String?,
                attachments: [ChatTranscriptAttachmentSnapshot]
            )
            case toolCall(
                sender: ChatTranscriptSenderPresentation,
                timestampISO: String,
                toolName: String?,
                input: String?
            )
            case toolResult(
                sender: ChatTranscriptSenderPresentation,
                timestampISO: String,
                toolName: String?,
                output: String?
            )
            case labeled(
                category: VisualCategory,
                kindLabel: String,
                sender: ChatTranscriptSenderPresentation,
                timestampISO: String,
                text: String,
                richTextFormat: String?
            )
        }

        var kind: Kind
    }

    var title: String
    var startedAtISO: String?
    var rows: [Row]
    var streamingAppendix: ChatTranscriptStreamingAppendix?
    var theme: ChatTranscriptExportTheme
}

enum ChatTranscriptExport {

    private struct RGBColor {
        let red: Int
        let green: Int
        let blue: Int

        var hex: String {
            String(format: "#%02X%02X%02X", red, green, blue)
        }

        func rgba(_ opacity: Double) -> String {
            let clamped = max(0, min(1, opacity))
            return "rgba(\(red), \(green), \(blue), \(String(format: "%.3f", clamped)))"
        }
    }

    private static let userAccent = RGBColor(red: 10, green: 132, blue: 255)

    private static func isoTimestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func senderPresentation(
        participantId: UUID?,
        conversation: Conversation,
        participantsById: [UUID: Participant]
    ) -> ChatTranscriptSenderPresentation {
        guard let participantId, let participant = participantsById[participantId] else {
            return ChatTranscriptSenderPresentation(
                displayName: "System",
                role: .system,
                iconName: nil,
                colorName: nil
            )
        }

        switch participant.type {
        case .user:
            return ChatTranscriptSenderPresentation(
                displayName: participant.displayName,
                role: .user,
                iconName: nil,
                colorName: nil
            )
        case .agentSession(let sessionId):
            let agent = (conversation.sessions ?? []).first { $0.id == sessionId }?.agent
            return ChatTranscriptSenderPresentation(
                displayName: participant.displayName,
                role: .agent,
                iconName: agent?.icon,
                colorName: agent?.color
            )
        case .remoteUser:
            return ChatTranscriptSenderPresentation(
                displayName: participant.displayName,
                role: .user,
                iconName: nil,
                colorName: nil
            )
        case .remoteAgent:
            return ChatTranscriptSenderPresentation(
                displayName: participant.displayName,
                role: .agent,
                iconName: "person.2.wave.2",
                colorName: nil
            )
        }
    }

    private static func attachments(from message: ConversationMessage) -> [ChatTranscriptAttachmentSnapshot] {
        (message.attachments ?? []).map {
            ChatTranscriptAttachmentSnapshot(
                fileName: $0.fileName,
                mediaType: $0.mediaType,
                fileSize: $0.fileSize,
                localFilePath: $0.localFilePath
            )
        }
    }

    static func snapshot(
        conversation: Conversation,
        messages: [ConversationMessage],
        participants: [Participant],
        streamingAppendix: ChatTranscriptStreamingAppendix?,
        theme: ChatTranscriptExportTheme = .default
    ) -> ChatTranscriptSnapshot {
        let title = conversation.topic?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Chat"
        let started = isoTimestamp(conversation.startedAt)
        let participantsById = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })

        var rows: [ChatTranscriptSnapshot.Row] = []
        rows.reserveCapacity(messages.count)

        for message in messages {
            let ts = isoTimestamp(message.timestamp)
            let sender = senderPresentation(
                participantId: message.senderParticipantId,
                conversation: conversation,
                participantsById: participantsById
            )
            switch message.type {
            case .chat:
                rows.append(ChatTranscriptSnapshot.Row(kind: .chat(
                    sender: sender,
                    timestampISO: ts,
                    text: message.text,
                    thinking: message.thinkingText.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty },
                    attachments: attachments(from: message)
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
                    category: .system,
                    kindLabel: "System",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text,
                    richTextFormat: nil
                )))
            case .peerMessage:
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    category: .peerMessage,
                    kindLabel: "Peer Message",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text,
                    richTextFormat: nil
                )))
            case .delegation:
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    category: .delegation,
                    kindLabel: "Delegation",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text,
                    richTextFormat: nil
                )))
            case .blackboardUpdate:
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    category: .blackboard,
                    kindLabel: "Blackboard",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text,
                    richTextFormat: nil
                )))
            case .taskEvent:
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    category: .task,
                    kindLabel: "Task",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text,
                    richTextFormat: nil
                )))
            case .workspaceEvent:
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    category: .workspace,
                    kindLabel: "Workspace",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text,
                    richTextFormat: nil
                )))
            case .agentInvite:
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    category: .agentInvite,
                    kindLabel: "Agent Invite",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text,
                    richTextFormat: nil
                )))
            case .question:
                let answerText = message.toolInput ?? ""
                let combined = answerText.isEmpty ? message.text : "\(message.text)\n\nAnswer: \(answerText)"
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    category: .question,
                    kindLabel: "Question",
                    sender: sender,
                    timestampISO: ts,
                    text: combined,
                    richTextFormat: "markdown"
                )))
            case .richContent:
                let format = message.toolName ?? "html"
                rows.append(ChatTranscriptSnapshot.Row(kind: .labeled(
                    category: .richContent,
                    kindLabel: "Rich Content (\(format))",
                    sender: sender,
                    timestampISO: ts,
                    text: message.text,
                    richTextFormat: format
                )))
            case .systemEvaluation:
                break
            }
        }

        let appendix = streamingAppendix.flatMap { $0.isEmpty ? nil : $0 }
        return ChatTranscriptSnapshot(
            title: title,
            startedAtISO: started,
            rows: rows,
            streamingAppendix: appendix,
            theme: theme
        )
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
            if let iconName = app.iconName, !iconName.isEmpty {
                parts[parts.count - 1] += " `\(iconName)`"
            }
            parts.append("")
            if !app.thinking.isEmpty {
                parts.append("### Thinking")
                parts.append("")
                parts.append(indentedBlock(app.thinking))
                parts.append("")
            }
            if !app.text.isEmpty {
                parts.append(sanitizeMarkdownBody(app.text))
                parts.append("")
            }
        }

        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func markdownLines(for row: ChatTranscriptSnapshot.Row) -> [String] {
        switch row.kind {
        case .chat(let sender, let ts, let text, let thinking, let attachments):
            var lines: [String] = []
            lines.append("## \(sender.displayName) · \(ts)")
            if let thinking, !thinking.isEmpty {
                lines.append("")
                lines.append("### Thinking")
                lines.append("")
                lines.append(indentedBlock(thinking))
            }
            if !attachments.isEmpty {
                lines.append("")
                lines.append("Attachments:")
                for attachment in attachments {
                    lines.append("- \(attachment.fileName) (\(attachment.mediaType), \(attachment.formattedSize))")
                }
            }
            if !text.isEmpty {
                lines.append("")
                lines.append(sanitizeMarkdownBody(text))
            }
            return lines
        case .toolCall(let sender, let ts, let toolName, let input):
            var lines: [String] = [
                "## Tool call · \(sender.displayName) · \(ts)",
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
                "## Tool result · \(sender.displayName) · \(ts)",
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
        case .labeled(let category, let label, let sender, let ts, let text, let richTextFormat):
            var lines: [String] = [
                "## \(label) · \(sender.displayName) · \(ts)",
                ""
            ]
            if category == .richContent, let richTextFormat, !richTextFormat.isEmpty {
                lines.append("_Format: \(richTextFormat)_")
                lines.append("")
            }
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
        body += "<div class=\"page-shell\">\n"
        body += "<header class=\"transcript-header\">\n"
        body += "<div>\n"
        body += "<p class=\"eyebrow\">Odyssey Chat Export</p>\n"
        body += "<h1>\(escapeHTML(snapshot.title))</h1>\n"
        if let started = snapshot.startedAtISO {
            body += "<p class=\"meta\">Started: \(escapeHTML(started))</p>\n"
        }
        body += "</div>\n"
        body += "<div class=\"export-pill \(snapshot.theme.appearance == .dark ? "is-dark" : "is-light")\">\(snapshot.theme.appearance.rawValue.capitalized) theme</div>\n"
        body += "</header>\n"

        if snapshot.rows.isEmpty, snapshot.streamingAppendix == nil {
            body += "<div class=\"empty-state\">No messages.</div>\n"
        } else {
            body += "<div class=\"transcript-list\">\n"
            for row in snapshot.rows {
                body += htmlBlock(for: row)
            }
            if let app = snapshot.streamingAppendix {
                body += htmlStreamingAppendix(app)
            }
            body += "</div>\n"
        }
        body += "</div>\n"

        return htmlDocument(pageTitle: snapshot.title, body: body, theme: snapshot.theme)
    }

    private static func htmlBlock(for row: ChatTranscriptSnapshot.Row) -> String {
        switch row.kind {
        case .chat(let sender, let ts, let text, let thinking, let attachments):
            let bubbleClass = bubbleClass(for: sender)
            var s = "<section class=\"row \(rowClass(for: sender))\">\n"
            s += htmlSenderLine(sender: sender, timestampISO: ts)
            s += "<article class=\"bubble \(bubbleClass)\" \(tintStyle(colorName: senderColorName(for: sender)))>\n"
            if let thinking, !thinking.isEmpty {
                s += htmlThinkingCard(thinking)
            }
            if !attachments.isEmpty {
                s += htmlAttachmentGrid(attachments)
            }
            if !text.isEmpty {
                s += "<div class=\"message-content\">\(htmlMessageBody(text))</div>\n"
            }
            s += "</article>\n"
            s += "</section>\n"
            return s
        case .toolCall(let sender, let ts, let toolName, let input):
            return htmlCardRow(
                sender: sender,
                timestampISO: ts,
                category: .toolCall,
                bodyHTML: htmlToolBody(toolName: toolName, primaryText: nil, code: input, codeLabel: "Input")
            )
        case .toolResult(let sender, let ts, let toolName, let output):
            return htmlCardRow(
                sender: sender,
                timestampISO: ts,
                category: .toolResult,
                bodyHTML: htmlToolBody(toolName: toolName, primaryText: nil, code: output, codeLabel: "Output")
            )
        case .labeled(let category, let label, let sender, let ts, let text, let richTextFormat):
            if category == .system {
                return """
                <section class="row row-system">
                <div class="system-pill">\(escapeHTML(text))</div>
                </section>
                """
            }

            let bodyHTML: String
            if category == .richContent {
                bodyHTML = htmlRichContentBody(text: text, format: richTextFormat)
            } else {
                bodyHTML = "<div class=\"message-content\">\(htmlMessageBody(text))</div>\n"
            }

            return htmlCardRow(
                sender: sender,
                timestampISO: ts,
                category: category,
                titleOverride: label,
                bodyHTML: bodyHTML
            )
        }
    }

    private static func htmlCardRow(
        sender: ChatTranscriptSenderPresentation,
        timestampISO: String,
        category: ChatTranscriptSnapshot.Row.VisualCategory,
        titleOverride: String? = nil,
        bodyHTML: String
    ) -> String {
        let title = titleOverride ?? category.label
        let tintName = category.colorName ?? senderColorName(for: sender)
        var s = "<section class=\"row \(rowClass(for: sender))\">\n"
        s += htmlSenderLine(sender: sender, timestampISO: timestampISO)
        s += "<article class=\"bubble bubble-card bubble-\(category.rawValue)\" \(tintStyle(colorName: tintName))>\n"
        s += "<div class=\"card-header\">\n"
        s += htmlIconBadge(iconName: category.iconName, colorName: tintName, fallbackText: title)
        s += "<span class=\"card-title\">\(escapeHTML(title))</span>\n"
        s += "</div>\n"
        s += bodyHTML
        s += "</article>\n"
        s += "</section>\n"
        return s
    }

    private static func htmlToolBody(toolName: String?, primaryText: String?, code: String?, codeLabel: String) -> String {
        var body = "<div class=\"tool-body\">\n"
        if let toolName, !toolName.isEmpty {
            body += "<p class=\"tool-label\"><span>Tool</span><code>\(escapeHTML(toolName))</code></p>\n"
        }
        if let primaryText, !primaryText.isEmpty {
            body += "<div class=\"message-content\">\(htmlMessageBody(primaryText))</div>\n"
        }
        if let code, !code.isEmpty {
            body += htmlCodeBlock(title: codeLabel, language: nil, code: code)
        }
        body += "</div>\n"
        return body
    }

    private static func htmlRichContentBody(text: String, format: String?) -> String {
        let normalized = (format ?? "html").lowercased()
        switch normalized {
        case "markdown":
            return "<div class=\"message-content\">\(htmlMessageBody(text))</div>\n"
        case "mermaid":
            return """
            <div class="tool-body">
            <p class="tool-label"><span>Format</span><code>mermaid</code></p>
            \(htmlCodeBlock(title: "Diagram Source", language: "mermaid", code: text))
            </div>
            """
        case "html":
            return """
            <div class="tool-body">
            <p class="tool-label"><span>Format</span><code>html</code></p>
            \(htmlCodeBlock(title: "HTML", language: "html", code: text))
            </div>
            """
        default:
            return """
            <div class="tool-body">
            <p class="tool-label"><span>Format</span><code>\(escapeHTML(normalized))</code></p>
            \(htmlCodeBlock(title: "Content", language: normalized, code: text))
            </div>
            """
        }
    }

    private static func htmlStreamingAppendix(_ appendix: ChatTranscriptStreamingAppendix) -> String {
        let sender = ChatTranscriptSenderPresentation(
            displayName: appendix.displayName,
            role: .agent,
            iconName: appendix.iconName,
            colorName: appendix.colorName
        )
        var s = "<section class=\"row \(rowClass(for: sender))\">\n"
        s += htmlSenderLine(sender: sender, timestampISO: "In progress")
        s += "<article class=\"bubble bubble-card bubble-streaming\" \(tintStyle(colorName: appendix.colorName ?? ChatTranscriptSnapshot.Row.VisualCategory.streaming.colorName))>\n"
        s += "<div class=\"card-header\">\n"
        s += htmlIconBadge(
            iconName: ChatTranscriptSnapshot.Row.VisualCategory.streaming.iconName,
            colorName: appendix.colorName ?? ChatTranscriptSnapshot.Row.VisualCategory.streaming.colorName,
            fallbackText: "In Progress"
        )
        s += "<span class=\"card-title\">In progress (not yet saved)</span>\n"
        s += "</div>\n"
        if !appendix.thinking.isEmpty {
            s += htmlThinkingCard(appendix.thinking)
        }
        if !appendix.text.isEmpty {
            s += "<div class=\"message-content\">\(htmlMessageBody(appendix.text))</div>\n"
        }
        s += "</article>\n"
        s += "</section>\n"
        return s
    }

    private static func htmlThinkingCard(_ thinking: String) -> String {
        """
        <section class="thinking-card">
        <div class="thinking-header">
        \(htmlIconBadge(iconName: "brain", colorName: "indigo", fallbackText: "Thinking"))
        <span>Thinking</span>
        </div>
        <div class="thinking-body">\(htmlMessageBody(thinking))</div>
        </section>
        """
    }

    private static func htmlAttachmentGrid(_ attachments: [ChatTranscriptAttachmentSnapshot]) -> String {
        let cards = attachments.map { attachment -> String in
            if attachment.isImage, let dataURL = imageDataURL(for: attachment) {
                return """
                <figure class="attachment-card attachment-image">
                <img src="\(dataURL)" alt="\(escapeHTML(attachment.fileName))"/>
                <figcaption>
                <span class="attachment-name">\(escapeHTML(attachment.fileName))</span>
                <span class="attachment-meta">\(escapeHTML(attachment.formattedSize))</span>
                </figcaption>
                </figure>
                """
            }

            return """
            <div class="attachment-card attachment-file">
            \(htmlIconBadge(iconName: attachment.iconName, colorName: "blue", fallbackText: attachment.fileName))
            <div>
            <div class="attachment-name">\(escapeHTML(attachment.fileName))</div>
            <div class="attachment-meta">\(escapeHTML(attachment.mediaType)) · \(escapeHTML(attachment.formattedSize))</div>
            </div>
            </div>
            """
        }.joined(separator: "\n")

        return "<div class=\"attachment-grid\">\n\(cards)\n</div>\n"
    }

    private static func htmlSenderLine(sender: ChatTranscriptSenderPresentation, timestampISO: String) -> String {
        var s = "<div class=\"sender-line\" \(tintStyle(colorName: senderColorName(for: sender)))>\n"
        if sender.role != .user {
            s += htmlIconBadge(
                iconName: sender.iconName,
                colorName: senderColorName(for: sender),
                fallbackText: sender.displayName
            )
        }
        s += "<span class=\"sender-name\">\(escapeHTML(sender.displayName))</span>\n"
        s += "<span class=\"sender-time\">\(escapeHTML(timestampISO))</span>\n"
        s += "</div>\n"
        return s
    }

    private static func senderColorName(for sender: ChatTranscriptSenderPresentation) -> String? {
        switch sender.role {
        case .user:
            return "accent"
        case .agent:
            return sender.colorName
        case .system:
            return nil
        }
    }

    private static func rowClass(for sender: ChatTranscriptSenderPresentation) -> String {
        switch sender.role {
        case .user:
            return "row-user"
        case .system:
            return "row-system"
        case .agent:
            return "row-agent"
        }
    }

    private static func bubbleClass(for sender: ChatTranscriptSenderPresentation) -> String {
        switch sender.role {
        case .user:
            return "bubble-chat bubble-user"
        case .system:
            return "bubble-chat bubble-system"
        case .agent:
            return "bubble-chat bubble-agent"
        }
    }

    private static func tintStyle(colorName: String?) -> String {
        guard let colorName, let color = colorValue(named: colorName) else { return "" }
        return """
        style="--sender-color: \(color.hex); --sender-soft: \(color.rgba(0.12)); --sender-soft-strong: \(color.rgba(0.18)); --sender-border: \(color.rgba(0.26));"
        """
    }

    private static func htmlIconBadge(iconName: String?, colorName: String?, fallbackText: String) -> String {
        guard let iconName, !iconName.isEmpty else {
            let letter = escapeHTML(String(fallbackText.prefix(1)).uppercased())
            return "<span class=\"icon-fallback\">\(letter)</span>"
        }

        if let dataURL = symbolDataURL(symbolName: iconName, colorName: colorName) {
            return "<span class=\"icon-badge\"><img src=\"\(dataURL)\" alt=\"\"/></span>"
        }

        let letter = escapeHTML(String(fallbackText.prefix(1)).uppercased())
        return "<span class=\"icon-fallback\">\(letter)</span>"
    }

    private static func symbolDataURL(symbolName: String, colorName: String?) -> String? {
        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold)) else {
            return nil
        }

        let rendered = renderSymbolImage(image, tint: nsColor(named: colorName ?? "accent"))
        guard let tiff = rendered.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            return nil
        }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    private static func renderSymbolImage(_ image: NSImage, tint: NSColor) -> NSImage {
        let rendered = NSImage(size: image.size)
        rendered.lockFocus()
        let rect = NSRect(origin: .zero, size: image.size)
        tint.set()
        rect.fill()
        image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        rendered.unlockFocus()
        rendered.isTemplate = false
        return rendered
    }

    private static func imageDataURL(for attachment: ChatTranscriptAttachmentSnapshot) -> String? {
        guard let localFilePath = attachment.localFilePath,
              FileManager.default.fileExists(atPath: localFilePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: localFilePath)) else {
            return nil
        }
        return "data:\(attachment.mediaType);base64,\(data.base64EncodedString())"
    }

    private static func htmlCodeBlock(title: String, language: String?, code: String) -> String {
        var label = escapeHTML(title)
        if let language, !language.isEmpty {
            label += " · \(escapeHTML(language))"
        }
        return """
        <section class="code-block">
        <div class="code-header">\(label)</div>
        <pre><code>\(escapeHTML(code))</code></pre>
        </section>
        """
    }

    private static func htmlMessageBody(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if let blocks = AdmonitionParser.extractBlocks(from: normalized), !blocks.isEmpty {
            return blocks.map { block in
                switch block {
                case .markdown(let markdownText):
                    return renderMarkdownBlocks(markdownText)
                case .admonition(let kind, let title, let body):
                    return renderAdmonition(kind: kind, title: title, body: body)
                }
            }
            .joined(separator: "\n")
        }
        return renderMarkdownBlocks(normalized)
    }

    private static func renderAdmonition(kind: AdmonitionKind, title: String, body: String) -> String {
        let displayTitle = title.isEmpty ? kind.defaultTitle : title
        let colorName = colorName(for: kind)
        return """
        <section class="admonition-card" \(tintStyle(colorName: colorName))>
        <div class="admonition-header">
        \(htmlIconBadge(iconName: kind.icon, colorName: colorName, fallbackText: displayTitle))
        <span>\(escapeHTML(displayTitle))</span>
        </div>
        <div class="admonition-body">\(renderMarkdownBlocks(body))</div>
        </section>
        """
    }

    private static func renderMarkdownBlocks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var html: [String] = []
        var index = 0

        func isSpecial(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { return true }
            if trimmed.hasPrefix("```") { return true }
            if trimmed.hasPrefix(">") { return true }
            if isTableHeader(at: index, in: lines) { return true }
            if headingLevel(for: trimmed) != nil { return true }
            if listKind(for: trimmed) != nil { return true }
            return false
        }

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                html.append("<hr class=\"md-rule\"/>")
                index += 1
                continue
            }

            if isTableHeader(at: index, in: lines) {
                let headerCells = splitTableCells(from: lines[index])
                let alignments = tableAlignments(from: lines[index + 1]) ?? Array(repeating: nil, count: headerCells.count)
                index += 2

                var bodyRows: [[String]] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.isEmpty || !isTableRow(candidate, expectedColumnCount: headerCells.count) {
                        break
                    }
                    bodyRows.append(splitTableCells(from: lines[index], expectedCount: headerCells.count))
                    index += 1
                }

                html.append(renderTable(header: headerCells, bodyRows: bodyRows, alignments: alignments))
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                html.append(htmlCodeBlock(title: language?.capitalized ?? "Code", language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            if let level = headingLevel(for: trimmed) {
                let content = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                html.append("<h\(level)>\(renderInlineMarkdown(content))</h\(level)>")
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                let inner = quoteLines.joined(separator: "\n")
                html.append("<blockquote>\(renderMarkdownBlocks(inner))</blockquote>")
                continue
            }

            if let currentListKind = listKind(for: trimmed) {
                var items: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard listKind(for: candidate) == currentListKind else { break }
                    items.append(stripListMarker(candidate, kind: currentListKind))
                    index += 1
                }
                let tag = currentListKind == .ordered ? "ol" : "ul"
                let itemsHTML = items
                    .map { "<li>\(renderInlineMarkdown($0))</li>" }
                    .joined(separator: "\n")
                html.append("<\(tag)>\n\(itemsHTML)\n</\(tag)>")
                continue
            }

            var paragraphLines: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let candidate = lines[index]
                if candidate.trimmingCharacters(in: .whitespaces).isEmpty || isSpecial(candidate) {
                    break
                }
                paragraphLines.append(candidate.trimmingCharacters(in: .whitespaces))
                index += 1
            }
            html.append("<p>\(renderInlineMarkdown(paragraphLines.joined(separator: "\n")))</p>")
        }

        return html.joined(separator: "\n")
    }

    private enum MarkdownListKind {
        case unordered
        case ordered
    }

    private static func isTableHeader(at index: Int, in lines: [String]) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        guard isTableRow(header, expectedColumnCount: nil) else { return false }
        guard let alignments = tableAlignments(from: lines[index + 1]) else { return false }
        return splitTableCells(from: lines[index]).count == alignments.count
    }

    private static func isTableRow(_ line: String, expectedColumnCount: Int?) -> Bool {
        guard line.contains("|") else { return false }
        let cells = splitTableCells(from: line)
        guard cells.count >= 2 else { return false }
        if let expectedColumnCount {
            return cells.count == expectedColumnCount
        }
        return true
    }

    private static func splitTableCells(from line: String, expectedCount: Int? = nil) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }

        var cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        if let expectedCount {
            if cells.count < expectedCount {
                cells.append(contentsOf: Array(repeating: "", count: expectedCount - cells.count))
            } else if cells.count > expectedCount {
                cells = Array(cells.prefix(expectedCount))
            }
        }

        return cells
    }

    private static func tableAlignments(from line: String) -> [String?]? {
        let cells = splitTableCells(from: line)
        guard !cells.isEmpty else { return nil }

        var alignments: [String?] = []
        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil else {
                return nil
            }
            if trimmed.hasPrefix(":") && trimmed.hasSuffix(":") {
                alignments.append("center")
            } else if trimmed.hasPrefix(":") {
                alignments.append("left")
            } else if trimmed.hasSuffix(":") {
                alignments.append("right")
            } else {
                alignments.append(nil)
            }
        }
        return alignments
    }

    private static func renderTable(header: [String], bodyRows: [[String]], alignments: [String?]) -> String {
        let headerHTML = zip(header.indices, header).map { index, cell in
            let alignment = tableCellAlignmentStyle(index < alignments.count ? alignments[index] : nil)
            return "<th\(alignment)>\(renderInlineMarkdown(cell))</th>"
        }
        .joined()

        let bodyHTML = bodyRows.map { row in
            let cells = zip(row.indices, row).map { index, cell in
                let alignment = tableCellAlignmentStyle(index < alignments.count ? alignments[index] : nil)
                return "<td\(alignment)>\(renderInlineMarkdown(cell))</td>"
            }
            .joined()
            return "<tr>\(cells)</tr>"
        }
        .joined(separator: "\n")

        return """
        <div class="table-wrap">
        <table>
        <thead><tr>\(headerHTML)</tr></thead>
        <tbody>
        \(bodyHTML)
        </tbody>
        </table>
        </div>
        """
    }

    private static func tableCellAlignmentStyle(_ alignment: String?) -> String {
        guard let alignment else { return "" }
        return " style=\"text-align: \(alignment);\""
    }

    private static func headingLevel(for line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let count = line.prefix { $0 == "#" }.count
        guard (1...3).contains(count), line.dropFirst(count).first == " " else { return nil }
        return count
    }

    private static func listKind(for line: String) -> MarkdownListKind? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return .unordered
        }
        if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            return .ordered
        }
        return nil
    }

    private static func stripListMarker(_ line: String, kind: MarkdownListKind) -> String {
        switch kind {
        case .unordered:
            return String(line.dropFirst(2))
        case .ordered:
            return line.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
        }
    }

    private static func renderInlineMarkdown(_ text: String) -> String {
        let escaped = escapeHTML(text).replacingOccurrences(of: "\n", with: "<br/>")
        var result = escaped

        var codeTokens: [String] = []
        result = result.replacingMatches(
            of: #"`([^`\n]+)`"#,
            with: { match in
                let code = match[1]
                let token = "%%CODE\(codeTokens.count)%%"
                codeTokens.append("<code>\(code)</code>")
                return token
            }
        )

        result = result.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)\s]+)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"__([^_]+)__"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?<!\*)\*([^*]+)\*(?!\*)"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?<!_)_([^_]+)_(?!_)"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )

        for (index, token) in codeTokens.enumerated() {
            result = result.replacingOccurrences(of: "%%CODE\(index)%%", with: token)
        }

        return result
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

    private static func colorName(for kind: AdmonitionKind) -> String {
        switch kind {
        case .note: return "blue"
        case .tip: return "teal"
        case .info: return "blue"
        case .success: return "green"
        case .warning, .caution: return "orange"
        case .error, .danger, .bug: return "red"
        case .example: return "purple"
        case .quote: return "gray"
        case .important: return "orange"
        case .abstract: return "indigo"
        }
    }

    private static func colorValue(named name: String) -> RGBColor? {
        switch name {
        case "accent": return userAccent
        case "blue": return RGBColor(red: 10, green: 132, blue: 255)
        case "red": return RGBColor(red: 255, green: 69, blue: 58)
        case "green": return RGBColor(red: 48, green: 209, blue: 88)
        case "purple": return RGBColor(red: 191, green: 90, blue: 242)
        case "orange": return RGBColor(red: 255, green: 159, blue: 10)
        case "yellow": return RGBColor(red: 255, green: 214, blue: 10)
        case "pink": return RGBColor(red: 255, green: 55, blue: 95)
        case "teal": return RGBColor(red: 90, green: 200, blue: 250)
        case "indigo": return RGBColor(red: 94, green: 92, blue: 230)
        case "gray": return RGBColor(red: 142, green: 142, blue: 147)
        default: return nil
        }
    }

    private static func nsColor(named name: String) -> NSColor {
        guard let rgb = colorValue(named: name) else { return .controlAccentColor }
        return NSColor(
            calibratedRed: CGFloat(rgb.red) / 255.0,
            green: CGFloat(rgb.green) / 255.0,
            blue: CGFloat(rgb.blue) / 255.0,
            alpha: 1
        )
    }

    private static func htmlDocument(pageTitle: String, body: String, theme: ChatTranscriptExportTheme) -> String {
        let isDark = theme.appearance == .dark
        let textScale = max(0.85, min(1.4, theme.textScale))
        let canvas = isDark ? "#0F1115" : "#F6F7FB"
        let panel = isDark ? "#161A22" : "#FFFFFF"
        let panelRaised = isDark ? "#1D2330" : "#FBFCFF"
        let text = isDark ? "#F3F5F7" : "#171A1F"
        let muted = isDark ? "#A7B0BE" : "#616B7C"
        let border = isDark ? "rgba(255,255,255,0.10)" : "rgba(15,23,42,0.10)"
        let shadow = isDark
            ? "0 18px 48px rgba(0,0,0,0.35)"
            : "0 18px 48px rgba(15,23,42,0.10)"
        let codeSurface = isDark ? "#1E2532" : "#F3F5F9"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>\(escapeHTML(pageTitle))</title>
        <style>
          :root {
            --text-scale: \(String(format: "%.3f", textScale));
            --canvas: \(canvas);
            --panel: \(panel);
            --panel-raised: \(panelRaised);
            --text: \(text);
            --muted: \(muted);
            --border: \(border);
            --shadow: \(shadow);
            --code-surface: \(codeSurface);
            --accent: \(userAccent.hex);
            --accent-soft: \(userAccent.rgba(0.15));
            --accent-border: \(userAccent.rgba(0.28));
            --indigo: #5E5CE6;
            --indigo-soft: rgba(94, 92, 230, 0.12);
            --indigo-border: rgba(94, 92, 230, 0.24);
          }
          * { box-sizing: border-box; }
          html, body {
            margin: 0;
            padding: 0;
            background: var(--canvas);
            color: var(--text);
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
            line-height: 1.5;
          }
          body { padding: 28px 22px 40px; }
          .page-shell {
            max-width: 1040px;
            margin: 0 auto;
          }
          .transcript-header {
            display: flex;
            justify-content: space-between;
            gap: 18px;
            align-items: flex-start;
            margin-bottom: 24px;
          }
          .eyebrow {
            margin: 0 0 8px;
            color: var(--muted);
            font-size: calc(12px * var(--text-scale));
            text-transform: uppercase;
            letter-spacing: 0.08em;
            font-weight: 700;
          }
          h1 {
            margin: 0;
            font-size: calc(28px * var(--text-scale));
            line-height: 1.15;
          }
          .meta {
            margin: 8px 0 0;
            color: var(--muted);
            font-size: calc(13px * var(--text-scale));
          }
          .export-pill {
            padding: 8px 12px;
            border-radius: 999px;
            border: 1px solid var(--border);
            background: var(--panel);
            color: var(--muted);
            font-size: calc(12px * var(--text-scale));
            font-weight: 600;
            white-space: nowrap;
          }
          .transcript-list {
            display: flex;
            flex-direction: column;
            gap: 16px;
          }
          .row {
            display: flex;
            flex-direction: column;
            max-width: 100%;
          }
          .row-user { align-items: flex-end; }
          .row-agent { align-items: flex-start; }
          .row-system { align-items: center; }
          .sender-line {
            display: flex;
            align-items: center;
            gap: 8px;
            margin: 0 0 6px;
            color: var(--sender-color, var(--muted));
            font-size: calc(12px * var(--text-scale));
          }
          .sender-name {
            font-weight: 600;
          }
          .sender-time {
            color: var(--muted);
            font-size: calc(11px * var(--text-scale));
          }
          .bubble {
            width: min(760px, 100%);
            background: var(--panel);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 12px 14px;
            box-shadow: var(--shadow);
            overflow: hidden;
          }
          .bubble-user {
            background: var(--accent-soft);
            border-color: var(--accent-border);
          }
          .bubble-agent {
            background: var(--sender-soft, var(--panel));
            border-color: var(--sender-border, var(--border));
          }
          .bubble-card {
            background: linear-gradient(180deg, var(--panel), var(--panel-raised));
          }
          .bubble-streaming {
            border-style: dashed;
          }
          .card-header {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 12px;
          }
          .card-title {
            font-size: calc(12px * var(--text-scale));
            font-weight: 700;
            color: var(--sender-color, var(--text));
            text-transform: uppercase;
            letter-spacing: 0.04em;
          }
          .system-pill {
            max-width: 680px;
            padding: 6px 12px;
            border-radius: 999px;
            background: var(--panel);
            border: 1px solid var(--border);
            color: var(--muted);
            font-size: calc(12px * var(--text-scale));
            font-style: italic;
          }
          .icon-badge,
          .icon-fallback {
            width: 22px;
            height: 22px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            border-radius: 999px;
            background: var(--sender-soft-strong, rgba(127,127,127,0.16));
            border: 1px solid var(--sender-border, var(--border));
            flex-shrink: 0;
          }
          .icon-badge img {
            width: 13px;
            height: 13px;
            display: block;
          }
          .icon-fallback {
            color: var(--sender-color, var(--text));
            font-size: calc(11px * var(--text-scale));
            font-weight: 700;
          }
          .message-content > :first-child,
          .thinking-body > :first-child,
          .admonition-body > :first-child {
            margin-top: 0;
          }
          .message-content > :last-child,
          .thinking-body > :last-child,
          .admonition-body > :last-child {
            margin-bottom: 0;
          }
          .message-content h1, .message-content h2, .message-content h3,
          .thinking-body h1, .thinking-body h2, .thinking-body h3,
          .admonition-body h1, .admonition-body h2, .admonition-body h3 {
            line-height: 1.2;
            margin: 14px 0 8px;
          }
          .message-content h1, .thinking-body h1, .admonition-body h1 { font-size: calc(24px * var(--text-scale)); }
          .message-content h2, .thinking-body h2, .admonition-body h2 { font-size: calc(20px * var(--text-scale)); }
          .message-content h3, .thinking-body h3, .admonition-body h3 { font-size: calc(17px * var(--text-scale)); }
          .message-content p,
          .thinking-body p,
          .admonition-body p {
            margin: 0 0 10px;
            font-size: calc(14px * var(--text-scale));
          }
          .message-content a,
          .thinking-body a,
          .admonition-body a {
            color: var(--accent);
            text-decoration: none;
          }
          .message-content blockquote,
          .thinking-body blockquote,
          .admonition-body blockquote {
            margin: 8px 0 12px;
            padding-left: 12px;
            border-left: 3px solid var(--accent-border);
            color: var(--muted);
            font-style: italic;
          }
          .message-content code,
          .thinking-body code,
          .admonition-body code,
          .tool-label code {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: calc(12px * var(--text-scale));
            background: var(--code-surface);
            border-radius: 6px;
            padding: 2px 6px;
          }
          .message-content ul,
          .message-content ol,
          .thinking-body ul,
          .thinking-body ol,
          .admonition-body ul,
          .admonition-body ol {
            margin: 0 0 12px 18px;
            padding: 0;
          }
          .table-wrap {
            margin: 0 0 12px;
            border-radius: 12px;
            border: 1px solid var(--border);
            background: var(--panel-raised);
            overflow-x: auto;
          }
          .message-content table,
          .thinking-body table,
          .admonition-body table {
            width: 100%;
            border-collapse: collapse;
            min-width: 320px;
          }
          .message-content thead,
          .thinking-body thead,
          .admonition-body thead {
            background: var(--panel);
          }
          .message-content th,
          .message-content td,
          .thinking-body th,
          .thinking-body td,
          .admonition-body th,
          .admonition-body td {
            padding: 9px 12px;
            border-bottom: 1px solid var(--border);
            font-size: calc(13px * var(--text-scale));
            vertical-align: top;
          }
          .message-content th,
          .thinking-body th,
          .admonition-body th {
            color: var(--text);
            font-weight: 700;
            text-align: left;
            white-space: nowrap;
          }
          .message-content tbody tr:last-child td,
          .thinking-body tbody tr:last-child td,
          .admonition-body tbody tr:last-child td {
            border-bottom: none;
          }
          .md-rule {
            border: none;
            border-top: 1px solid var(--border);
            margin: 14px 0;
          }
          .thinking-card {
            margin-bottom: 12px;
            border-radius: 12px;
            padding: 10px 11px;
            background: var(--indigo-soft);
            border: 1px solid var(--indigo-border);
          }
          .thinking-header {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 8px;
            color: var(--indigo);
            font-size: calc(12px * var(--text-scale));
            font-weight: 700;
          }
          .thinking-body {
            color: var(--muted);
          }
          .attachment-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 8px;
            margin-bottom: 12px;
          }
          .attachment-card {
            background: var(--panel-raised);
            border: 1px solid var(--border);
            border-radius: 12px;
            overflow: hidden;
          }
          .attachment-image img {
            display: block;
            width: 100%;
            max-height: 220px;
            object-fit: cover;
            background: var(--canvas);
          }
          .attachment-image figcaption,
          .attachment-file {
            padding: 10px 12px;
          }
          .attachment-file {
            display: flex;
            gap: 10px;
            align-items: flex-start;
          }
          .attachment-name {
            display: block;
            font-size: calc(12px * var(--text-scale));
            font-weight: 600;
          }
          .attachment-meta {
            display: block;
            margin-top: 2px;
            color: var(--muted);
            font-size: calc(11px * var(--text-scale));
          }
          .tool-body {
            display: flex;
            flex-direction: column;
            gap: 10px;
          }
          .tool-label {
            margin: 0;
            display: flex;
            gap: 8px;
            align-items: center;
            font-size: calc(12px * var(--text-scale));
            color: var(--muted);
          }
          .tool-label span {
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.04em;
          }
          .code-block {
            border-radius: 12px;
            overflow: hidden;
            border: 1px solid var(--border);
            background: var(--code-surface);
          }
          .code-header {
            padding: 8px 10px;
            border-bottom: 1px solid var(--border);
            color: var(--muted);
            font-size: calc(11px * var(--text-scale));
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.04em;
          }
          .code-block pre {
            margin: 0;
            padding: 12px;
            overflow-x: auto;
            white-space: pre-wrap;
            word-break: break-word;
          }
          .code-block pre code {
            background: transparent;
            border-radius: 0;
            padding: 0;
            font-size: calc(12px * var(--text-scale));
          }
          .admonition-card {
            margin: 8px 0 12px;
            border-radius: 12px;
            padding: 10px 12px;
            background: var(--sender-soft, rgba(127,127,127,0.10));
            border: 1px solid var(--sender-border, var(--border));
          }
          .admonition-header {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 8px;
            color: var(--sender-color, var(--text));
            font-size: calc(12px * var(--text-scale));
            font-weight: 700;
          }
          .empty-state {
            padding: 28px;
            border-radius: 18px;
            border: 1px dashed var(--border);
            color: var(--muted);
            background: var(--panel);
            text-align: center;
          }
          @media print {
            body {
              padding: 0;
              background: #ffffff;
            }
            .page-shell {
              max-width: none;
            }
            .row,
            .bubble,
            .attachment-card,
            .code-block,
            .admonition-card,
            .thinking-card {
              break-inside: avoid;
            }
          }
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

    func replacingMatches(
        of pattern: String,
        with replacer: ([String]) -> String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return self
        }

        let nsString = self as NSString
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return self }

        var result = self
        for match in matches.reversed() {
            var groups: [String] = []
            for index in 0..<match.numberOfRanges {
                let range = match.range(at: index)
                if range.location != NSNotFound {
                    groups.append(nsString.substring(with: range))
                } else {
                    groups.append("")
                }
            }
            let replacement = replacer(groups)
            if let swiftRange = Range(match.range, in: result) {
                result.replaceSubrange(swiftRange, with: replacement)
            }
        }
        return result
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
