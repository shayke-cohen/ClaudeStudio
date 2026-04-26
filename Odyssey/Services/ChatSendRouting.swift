import Foundation

enum ChatSlashCommand: Equatable {
    // existing
    case help
    case topic(String)
    case agents
    // session
    case clear
    case compact
    case export(format: String?)
    case resume
    // model
    case model(String?)
    case effort(String?)
    case fast
    // memory & skills
    case memory
    case skills
    // agents
    case mode(String?)
    case plan
    // tools
    case mcp
    case permissions
    // git
    case review
    case diff
    case branch(action: String?)
    case initialize
    // workflow
    case loop(interval: Int?)
    case schedule
    // info
    case context
    case cost
    // fallback
    case unknown(String)
}

enum ChatSendRouting {
    static let mentionAllToken = "all"

    /// First line only; returns nil if not a slash command.
    static func parseSlashCommand(_ raw: String) -> ChatSlashCommand? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "/", trimmed.count > 1 else { return nil }
        if trimmed.hasPrefix("//") { return nil }

        let firstLine = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? trimmed
        let parts = firstLine.dropFirst().split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let cmd = parts.first.map(String.init)?.lowercased() ?? ""

        let arg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : nil

        switch cmd {
        case "help", "?":
            return .help
        case "topic", "rename":
            return .topic(arg ?? "")
        case "agents":
            return .agents
        // session
        case "clear":
            return .clear
        case "compact":
            return .compact
        case "export":
            return .export(format: arg)
        case "resume":
            return .resume
        // model
        case "model":
            return .model(arg)
        case "effort":
            return .effort(arg)
        case "fast":
            return .fast
        // memory & skills
        case "memory":
            return .memory
        case "skills":
            return .skills
        // agents
        case "mode":
            return .mode(arg)
        case "plan":
            return .plan
        // tools
        case "mcp":
            return .mcp
        case "permissions":
            return .permissions
        // git
        case "review":
            return .review
        case "diff":
            return .diff
        case "branch":
            return .branch(action: arg)
        case "init":
            return .initialize
        // workflow
        case "loop":
            let interval = arg.flatMap { Int($0) }
            return .loop(interval: interval)
        case "schedule":
            return .schedule
        // info
        case "context":
            return .context
        case "cost":
            return .cost
        default:
            return .unknown(cmd)
        }
    }

    /// `@Name` tokens in send order. When agent definitions are provided, this
    /// greedily matches the longest installed agent name so mentions can include spaces.
    static func mentionedAgentNames(in text: String, agents: [Agent] = []) -> [String] {
        if agents.isEmpty {
            return simpleMentionTokens(in: text)
        }
        return mentionedAgentNames(in: text, preparedCandidates: prepareMentionCandidates(agents: agents))
    }

    /// Sorts agent display names by length-desc / name-asc once, so callers
    /// hitting `mentionedAgentNames` repeatedly (ChatView body, autocomplete,
    /// routing preview) don't re-sort on every keystroke.
    static func prepareMentionCandidates(agents: [Agent]) -> [String] {
        agents
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    /// Match against a previously-sorted candidate list. Use this when calling
    /// the matcher many times against the same agent set.
    static func mentionedAgentNames(in text: String, preparedCandidates: [String]) -> [String] {
        guard !preparedCandidates.isEmpty else {
            return simpleMentionTokens(in: text)
        }

        var mentions: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "@" else {
                index = text.index(after: index)
                continue
            }

            let mentionStart = text.index(after: index)
            let remaining = text[mentionStart...]

            if let allRange = mentionPrefixRange(for: mentionAllToken, in: remaining) {
                mentions.append(mentionAllToken)
                index = allRange.upperBound
                continue
            }

            if let matchedName = preparedCandidates.first(where: { mentionPrefixRange(for: $0, in: remaining) != nil }),
               let matchedRange = mentionPrefixRange(for: matchedName, in: remaining) {
                mentions.append(matchedName)
                index = matchedRange.upperBound
                continue
            }

            if let (unknownToken, unknownRange) = simpleMentionToken(in: remaining) {
                mentions.append(unknownToken)
                index = unknownRange.upperBound
                continue
            }

            index = mentionStart
        }

        return mentions
    }

    private static func simpleMentionTokens(in text: String) -> [String] {
        let pattern = #"@([^\s@]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { m in
            guard m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    /// Returns true if the text contains `@all`.
    static func containsMentionAll(in text: String) -> Bool {
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "@" else {
                index = text.index(after: index)
                continue
            }

            let mentionStart = text.index(after: index)
            let remaining = text[mentionStart...]
            if mentionPrefixRange(for: mentionAllToken, in: remaining) != nil {
                return true
            }
            index = mentionStart
        }
        return false
    }

    /// Match mention names to agents (exact name, case-insensitive).
    static func resolveMentionedAgents(names: [String], agents: [Agent]) -> (resolved: [Agent], unknown: [String]) {
        var resolved: [Agent] = []
        var unknown: [String] = []
        for raw in names {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if isMentionAllToken(key) { continue }
            if let a = agents.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) {
                if !resolved.contains(where: { $0.id == a.id }) {
                    resolved.append(a)
                }
            } else {
                unknown.append(key)
            }
        }
        return (resolved, unknown)
    }

    static func isMentionAllToken(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(mentionAllToken) == .orderedSame
    }

    private static func mentionPrefixRange(
        for candidate: String,
        in text: Substring
    ) -> Range<Substring.Index>? {
        guard !candidate.isEmpty,
              let range = text.range(of: candidate, options: [.anchored, .caseInsensitive]),
              isMentionBoundary(after: range.upperBound, in: text) else {
            return nil
        }
        return range
    }

    private static func isMentionBoundary(
        after index: Substring.Index,
        in text: Substring
    ) -> Bool {
        guard index < text.endIndex else { return true }
        let nextCharacter = text[index]
        return nextCharacter.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.alphanumerics.contains(scalar)
        }
    }

    private static func simpleMentionToken(
        in text: Substring
    ) -> (token: String, range: Range<Substring.Index>)? {
        guard !text.isEmpty else { return nil }

        var end = text.startIndex
        while end < text.endIndex {
            let character = text[end]
            if character == "@" || character.isWhitespace {
                break
            }
            end = text.index(after: end)
        }

        guard end > text.startIndex else { return nil }
        return (String(text[text.startIndex..<end]), text.startIndex..<end)
    }
}
