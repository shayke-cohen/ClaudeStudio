import Foundation

/// Utilities for Resident Agent filesystem support.
/// A "Resident Agent" is any Agent whose `defaultWorkingDirectory` is non-nil.
///
/// Each resident gets a tiered knowledge vault in their home folder:
///
///   CLAUDE.md     — auto-loaded by Claude Code; identity + graph conventions + reflection loop
///   INDEX.md      — map-of-content; updated whenever a new file is added
///   MEMORY.md     — routing index (200-line cap); dated one-liners + domain map
///   GUIDELINES.md — self-written rules with #tags and frontmatter
///   SESSION.md    — volatile active state; reset at each session start
///   sessions/     — episodic: append-only daily logs (agent-grown)
///   knowledge/    — semantic: topic notes promoted from sessions (agent-grown)
enum ResidentAgentSupport {

    // MARK: - Seed vault (call on promotion)

    /// Seeds all vault files in the agent's home folder. Safe to call multiple times — each file
    /// is only created once; existing files are never overwritten.
    static func seedVaultIfNeeded(in directoryPath: String, agentName: String) {
        seedMemoryFileIfNeeded(in: directoryPath, agentName: agentName)
        seedCLAUDEFileIfNeeded(in: directoryPath, agentName: agentName)
        seedIndexFileIfNeeded(in: directoryPath, agentName: agentName)
        seedGuidelinesFileIfNeeded(in: directoryPath)
        seedSessionFileIfNeeded(in: directoryPath)
    }

    // MARK: - Session start (call when opening a resident session)

    /// Ensures all vault files exist and resets the volatile SESSION.md.
    /// Call this each time a resident session is started.
    static func prepareVaultForSession(in directoryPath: String, agentName: String) {
        seedVaultIfNeeded(in: directoryPath, agentName: agentName)
        resetSessionFile(in: directoryPath)
    }

    // MARK: - Individual seed functions

    /// Creates `MEMORY.md` if it does not already exist.
    @discardableResult
    static func seedMemoryFileIfNeeded(in directoryPath: String, agentName: String) -> Bool {
        seedFileIfNeeded(named: "MEMORY.md", in: directoryPath, content: memoryTemplate(agentName: agentName))
    }

    /// Creates `CLAUDE.md` if it does not already exist.
    @discardableResult
    static func seedCLAUDEFileIfNeeded(in directoryPath: String, agentName: String) -> Bool {
        seedFileIfNeeded(named: "CLAUDE.md", in: directoryPath, content: claudeTemplate(agentName: agentName))
    }

    /// Creates `INDEX.md` if it does not already exist.
    @discardableResult
    static func seedIndexFileIfNeeded(in directoryPath: String, agentName: String) -> Bool {
        seedFileIfNeeded(named: "INDEX.md", in: directoryPath, content: indexTemplate(agentName: agentName))
    }

    /// Creates `GUIDELINES.md` if it does not already exist.
    @discardableResult
    static func seedGuidelinesFileIfNeeded(in directoryPath: String) -> Bool {
        seedFileIfNeeded(named: "GUIDELINES.md", in: directoryPath, content: guidelinesTemplate())
    }

    /// Creates `SESSION.md` if it does not already exist.
    @discardableResult
    static func seedSessionFileIfNeeded(in directoryPath: String) -> Bool {
        seedFileIfNeeded(named: "SESSION.md", in: directoryPath, content: sessionTemplate())
    }

    /// Always overwrites `SESSION.md` — it is volatile and reset at each session start.
    @discardableResult
    static func resetSessionFile(in directoryPath: String) -> Bool {
        let fileURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
            .appendingPathComponent("SESSION.md")
        do {
            try sessionTemplate().write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private helpers

    @discardableResult
    private static func seedFileIfNeeded(named fileName: String, in directoryPath: String, content: String) -> Bool {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let fileURL = dirURL.appendingPathComponent(fileName)
        guard !fm.fileExists(atPath: fileURL.path) else { return false }
        do {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private static var isoDate: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: Date())
    }

    // MARK: - Templates

    static func memoryTemplate(agentName: String) -> String {
        """
        ---
        updated: \(isoDate)
        cap: "200 lines — keep under this cap; move detail to knowledge/"
        ---

        # \(agentName) — Memory

        ## Recent Lessons
        <!-- Dated one-liners. Format: YYYY-MM-DD: <lesson> -->

        ## Domain Map
        <!-- Routing table to knowledge/ files.
             Example: Auth → [[knowledge/auth.md]] -->

        ## Active Goals
        <!-- What this agent is currently focused on -->
        """
    }

    static func claudeTemplate(agentName: String) -> String {
        """
        ---
        agent: \(agentName)
        updated: \(isoDate)
        ---

        # \(agentName)

        ## Role
        <!-- What this agent is here to do. Fill and maintain this. -->

        ## Capabilities
        <!-- What this agent is good at. Update as capabilities grow. -->

        ## Knowledge Graph

        This directory is your persistent memory. Files use YAML frontmatter and [[wiki-links]].
        Use Grep to search across files when past context is needed.

        | File | Purpose | Cap |
        |------|---------|-----|
        | `INDEX.md` | Map of content — read first each session | — |
        | `MEMORY.md` | Routing index + recent lessons | 200 lines |
        | `GUIDELINES.md` | Self-written rules with #tags | — |
        | `SESSION.md` | Current active state (volatile) | Reset each session |
        | `sessions/YYYY-MM-DD.md` | Append-only daily session log | — |
        | `knowledge/{topic}.md` | Semantic topic notes | — |

        ## Session Start

        1. Read `INDEX.md` — understand what exists in the graph
        2. Read `MEMORY.md` — load routing index and recent lessons
        3. Read `GUIDELINES.md` — apply your self-written rules
        4. Reset `SESSION.md` — write current task and what NOT to forget
        5. Grep `sessions/` or `knowledge/` for topics relevant to today

        ## During Session

        - Insight discovered → append to `sessions/YYYY-MM-DD.md` with date and `#tag`
        - Error solved → append with `#error` tag
        - Focus shifts → update `SESSION.md`

        ## Session End — Reflection Loop

        Answer before closing:
        1. What was the task? Did it succeed?
        2. What was the earliest friction or mistake?
        3. What one rule would prevent it next time?

        Then:
        - Write a one-liner to `MEMORY.md`: `YYYY-MM-DD: <lesson>`
        - Write a full reflection entry to today's session file
        - If a pattern has recurred 2+ times across sessions → promote to `knowledge/{topic}.md`
        - Update `INDEX.md` if any new file was created

        ## Frontmatter Convention

        Use in all knowledge files:

        ```yaml
        ---
        type: pattern|decision|bug-fix|guideline|reference
        tags: [topic]
        status: active|deprecated
        confidence: high|medium|low
        related: [[file]]
        updated: YYYY-MM-DD
        ---
        ```
        """
    }

    static func indexTemplate(agentName: String) -> String {
        """
        ---
        updated: \(isoDate)
        ---

        # \(agentName) — Knowledge Index

        ## Core Files
        - [[CLAUDE.md]] — identity, graph conventions, and reflection loop
        - [[MEMORY.md]] — routing index and recent lessons
        - [[GUIDELINES.md]] — self-written rules
        - [[SESSION.md]] — current active state (volatile)

        ## Sessions (Episodic)
        <!-- Links added automatically as sessions/ files are created -->

        ## Knowledge (Semantic)
        <!-- Add links here when creating knowledge/ files -->
        """
    }

    static func guidelinesTemplate() -> String {
        """
        ---
        updated: \(isoDate)
        tags: [guidelines]
        ---

        # Guidelines

        <!-- Imperative rules written from experience across sessions.
             Format: - #tag Rule statement (YYYY-MM-DD)
             Example: - #auth Always use PKCE for client-side OAuth (2026-04-17) -->
        """
    }

    static func sessionTemplate() -> String {
        """
        ---
        updated: \(isoDate)
        volatile: true
        ---

        # Current Session

        ## Task
        <!-- What I'm working on right now -->

        ## Active Context
        <!-- Key decisions and state for this session -->

        ## Do Not Forget
        <!-- Critical items to carry through this session -->
        """
    }
}
