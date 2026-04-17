import Foundation

struct SlashCommandInfo: Identifiable, Equatable {
    let id: String          // matches the command name, e.g. "clear"
    let name: String        // display name e.g. "clear"
    let description: String
    let group: SlashCommandGroup
    let hasSubPicker: Bool

    var fullCommand: String { "/\(name)" }
}

enum SlashCommandGroup: String, CaseIterable {
    case session = "Session"
    case model = "Model"
    case memorySkills = "Memory & Skills"
    case agents = "Agents"
    case tools = "Tools"
    case git = "Git"
    case workflow = "Workflow"
    case info = "Info"
}

enum SlashCommandRegistry {
    static let all: [SlashCommandInfo] = [
        // Session
        .init(id: "clear",       name: "clear",       description: "Start a fresh conversation",          group: .session,       hasSubPicker: false),
        .init(id: "compact",     name: "compact",     description: "Compress context to save space",       group: .session,       hasSubPicker: false),
        .init(id: "export",      name: "export",      description: "Export transcript (md / html / json)", group: .session,       hasSubPicker: true),
        .init(id: "resume",      name: "resume",      description: "Resume a previous session",            group: .session,       hasSubPicker: true),
        // Model
        .init(id: "model",       name: "model",       description: "Switch Claude model",                  group: .model,         hasSubPicker: true),
        .init(id: "effort",      name: "effort",      description: "Set effort level (low/medium/high/max)", group: .model,       hasSubPicker: true),
        .init(id: "fast",        name: "fast",        description: "Toggle fast mode (effort low)",         group: .model,         hasSubPicker: false),
        // Memory & Skills
        .init(id: "memory",      name: "memory",      description: "View / edit agent memory file",        group: .memorySkills,  hasSubPicker: false),
        .init(id: "skills",      name: "skills",      description: "Toggle skills for this conversation",  group: .memorySkills,  hasSubPicker: false),
        // Agents
        .init(id: "agents",      name: "agents",      description: "Add agents to this conversation",      group: .agents,        hasSubPicker: false),
        .init(id: "mode",        name: "mode",        description: "Switch agent mode",                    group: .agents,        hasSubPicker: true),
        .init(id: "plan",        name: "plan",        description: "Enter plan mode",                      group: .agents,        hasSubPicker: false),
        // Tools
        .init(id: "mcp",         name: "mcp",         description: "Toggle MCP servers",                   group: .tools,         hasSubPicker: false),
        .init(id: "permissions", name: "permissions", description: "View active permission rules",         group: .tools,         hasSubPicker: false),
        // Git
        .init(id: "review",      name: "review",      description: "Review current git changes",           group: .git,           hasSubPicker: false),
        .init(id: "diff",        name: "diff",        description: "Show git diff for this session",       group: .git,           hasSubPicker: false),
        .init(id: "branch",      name: "branch",      description: "Create, switch, or list branches",     group: .git,           hasSubPicker: true),
        .init(id: "init",        name: "init",        description: "Initialize project with CLAUDE.md",    group: .git,           hasSubPicker: false),
        // Workflow
        .init(id: "loop",        name: "loop",        description: "Repeat a prompt on an interval",       group: .workflow,      hasSubPicker: true),
        .init(id: "schedule",    name: "schedule",    description: "Schedule a recurring mission",         group: .workflow,      hasSubPicker: false),
        // Info
        .init(id: "context",     name: "context",     description: "Show context window usage",            group: .info,          hasSubPicker: false),
        .init(id: "cost",        name: "cost",        description: "Show session token cost",              group: .info,          hasSubPicker: false),
        .init(id: "help",        name: "help",        description: "Show all slash commands",              group: .info,          hasSubPicker: false),
    ]

    /// Returns suggestions filtered by query, preserving group order.
    /// Empty query returns all commands.
    static func suggestions(for query: String) -> [SlashCommandInfo] {
        let q = query.lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.contains(q) || $0.description.lowercased().contains(q) }
    }

    /// Commands grouped for display, filtered by query.
    static func groupedSuggestions(for query: String) -> [(group: SlashCommandGroup, commands: [SlashCommandInfo])] {
        let filtered = suggestions(for: query)
        return SlashCommandGroup.allCases.compactMap { group in
            let cmds = filtered.filter { $0.group == group }
            return cmds.isEmpty ? nil : (group, cmds)
        }
    }
}
