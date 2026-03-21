# ClaudPeer — Functional Specification

Living specification tracking implemented features, user flows, and requirements.

**Version:** 0.6.0
**Status:** Phase 6 complete (UX Redesign + Inspector Toggle)

---

## 1. Product Summary

ClaudPeer is a native macOS developer tool for managing multiple Claude AI agent sessions. Users define reusable agent templates with skills, MCP servers, and permissions, then launch interactive sessions that stream AI responses in real-time through a chat interface.

### Target Users
- Developers using Claude for coding tasks who want persistent, configurable agent sessions
- Teams wanting to share agent definitions across machines (planned)

### Core Value Proposition
- **Multi-agent orchestration** — run multiple Claude sessions simultaneously with different configurations
- **Composable agents** — build agents from reusable skills, MCP servers, and permission presets
- **Curated catalog** — browse and install from 30 agents, 101 skills, and 100 MCP servers with cascading dependency resolution
- **Persistent conversations** — conversations survive app restarts, resumable via Claude session IDs
- **Native macOS experience** — SwiftUI three-panel layout optimized for developer workflows

---

## 2. Functional Requirements

### FR-1: Sidecar Lifecycle Management

**Status:** Implemented

The app manages a TypeScript sidecar process that hosts Claude Agent SDK sessions.

| Requirement | Status |
|---|---|
| FR-1.1: Auto-launch Bun sidecar on app start | Done |
| FR-1.2: WebSocket connection on localhost:9849 | Done |
| FR-1.3: Auto-reconnect on WebSocket disconnect | Done |
| FR-1.4: Relaunch sidecar if process terminates | Done |
| FR-1.5: Try connecting to existing sidecar before launching new one | Done |
| FR-1.6: Log sidecar output to ~/.claudpeer/logs/sidecar.log | Done |
| FR-1.7: Find Bun at standard paths (Homebrew, ~/.bun/bin) | Done |
| FR-1.8: Find sidecar at bundle, cwd, ~/ClaudPeer, or UserDefaults path | Done |
| FR-1.9: Graceful shutdown on app exit | Done |
| FR-1.10: Connection status reflected in UI (AppState.sidecarStatus) | Done |

### FR-2: Agent Management

**Status:** Implemented (basic CRUD)

Users create and manage reusable agent templates.

| Requirement | Status |
|---|---|
| FR-2.1: Create agent with name, description, system prompt | Done |
| FR-2.2: Configure model (sonnet, opus, haiku) | Done |
| FR-2.3: Set max turns and budget limits | Done |
| FR-2.4: Assign skills from pool (by ID reference) | Done |
| FR-2.5: Assign MCP servers from pool (by ID reference) | Done |
| FR-2.6: Assign permission set (by ID reference) | Done |
| FR-2.7: Set instance policy (spawn/singleton/pool) | Done (model) |
| FR-2.8: Set default working directory | Done |
| FR-2.9: Link GitHub repo and default branch | Done |
| FR-2.10: Set icon and color (9 colors: blue, red, green, purple, orange, teal, pink, indigo, gray) | Done |
| FR-2.11: Agent library grid view | Done |
| FR-2.12: Agent editor view with sheet(item:) presentation for editing | Done |
| FR-2.13: Persist agents in SwiftData | Done |
| FR-2.14: Built-in agents loaded from bundled JSON (7 agents) | Superseded by FR-12 |
| FR-2.15: Per-agent system prompts loaded from dedicated .md files | Done |
| FR-2.16: Agent → Skill → MCP dependency hierarchy (skills declare MCPs, agents select skills) | Done |
| FR-2.17: Duplicate agent with full config copy | Done |
| FR-2.18: catalogId tracking for catalog-originating agents | Done |

### FR-3: Session Lifecycle

**Status:** Implemented

All sessions use the Claude Agent SDK. Every session gets PeerBus tools injected automatically.

| Requirement | Status |
|---|---|
| FR-3.1: Create session from agent + optional mission | Done |
| FR-3.2: Resolve working directory (explicit/GitHub/default/ephemeral) | Done |
| FR-3.3: Provision AgentConfig from SwiftData models | Done |
| FR-3.4: Send session.create command to sidecar | Done |
| FR-3.5: Send messages to active sessions | Done |
| FR-3.6: Receive streaming tokens from sidecar | Done |
| FR-3.7: Receive tool call/result events | Done |
| FR-3.8: Receive session result with cost | Done |
| FR-3.9: Handle session errors | Done |
| FR-3.10: Resume sessions via Claude session ID | Done |
| FR-3.11: Fork sessions (branch conversation) | Done |
| FR-3.12: Pause/abort running sessions | Done |
| FR-3.13: Track session status (active/paused/completed/failed) | Done |
| FR-3.14: Instance policy enforcement (delegation respects definitions) | Partial |
| FR-3.15: All sessions use Agent SDK with PeerBus MCP server injected | Done |
| FR-3.16: Agent definitions registered with sidecar on connect (agent.register) | Done |
| FR-3.17: Response polling in Swift to capture agent replies and save to SwiftData | Done |
| FR-3.18: Autonomous session spawning for delegation (spawnAutonomous) | Done |

### FR-4: Conversation Model

**Status:** Implemented

Unified conversation model supporting user-to-agent and agent-to-agent communication.

| Requirement | Status |
|---|---|
| FR-4.1: Create conversation with participants | Done |
| FR-4.2: Persist messages in SwiftData | Done |
| FR-4.3: Message types: text, toolCall, toolResult, delegation, blackboard | Done |
| FR-4.4: Participant types: user, agentSession | Done |
| FR-4.5: Participant roles: active, observer | Done (model) |
| FR-4.6: Parent-child conversation tree (spawned conversations) | Done |
| FR-4.7: Conversation status (active/closed) | Done |
| FR-4.8: Agent-to-agent conversations (created from peer.chat/peer.delegate events) | Done |
| FR-4.9: Group conversations (user + multiple agents) | Not started |

### FR-5: Chat UI

**Status:** Implemented

| Requirement | Status |
|---|---|
| FR-5.1: Display conversation messages in chronological order | Done |
| FR-5.2: Text input with send button | Done |
| FR-5.3: Streaming text display during agent response | Done |
| FR-5.4: Tool call blocks (collapsible) | Done |
| FR-5.5: Message bubbles with participant distinction | Done |
| FR-5.6: Conversation tree node component | Done |
| FR-5.7: Status badges (session/conversation) | Done |
| FR-5.8: Slash commands in input | Not started |
| FR-5.9: File drag-and-drop (images + documents) | Done |
| FR-5.10: @-mention agents in group chats | Not started |
| FR-5.11: Fork from any message point | Not started |
| FR-5.12: Auto-name conversations from first user message | Done |
| FR-5.13: Rename conversations via context menu, chat header, or inspector | Done |
| FR-5.14: Pin/unpin conversations in sidebar | Done |
| FR-5.15: Close and delete conversations via context menu | Done |
| FR-5.16: New Session sheet with agent/model/mode/mission/working-dir picker | Done |
| FR-5.17: Chat header actions (close, resume, clear, rename, model pill, live cost) | Done |
| FR-5.18: Rich markdown rendering for agent messages (MarkdownUI) | Done |
| FR-5.19: Code blocks with language label and copy-to-clipboard button | Done |
| FR-5.20: Live streaming text bubble (shows streamed text as it arrives, not just dots) | Done |
| FR-5.21: Hover-to-reveal copy button on any message | Done |
| FR-5.22: Hover-to-reveal timestamp (reduces visual noise) | Done |
| FR-5.23: Clickable links in agent responses (opens in default browser) | Done |
| FR-5.24: Inline images rendered via MarkdownUI | Done |
| FR-5.25: Custom MarkdownUI theme (.claudPeer) with styled headings, blockquotes, tables, code | Done |

### FR-6: Main Window Layout

**Status:** Implemented

| Requirement | Status |
|---|---|
| FR-6.1: Two-column NavigationSplitView (sidebar + detail HStack with chat + optional inspector) | Done |
| FR-6.2: Sidebar with conversation list | Done |
| FR-6.3: Sidebar with agent list section | Done |
| FR-6.4: Detail area showing ChatView (expands to full width when inspector hidden) | Done |
| FR-6.5: Inspector panel with session metadata (toggleable) | Done |
| FR-6.6: Toolbar: new session, quick chat, sidecar status pill, inspector toggle | Done |
| FR-6.7: Default window size 1200x800 | Done |
| FR-6.8: Sidebar rows show relative timestamps, message preview, and agent icon | Done |
| FR-6.9: Sidebar has Pinned section above Active | Done |
| FR-6.10: Sidebar conversation context menu (rename, pin, close, delete, duplicate) | Done |
| FR-6.11: Sidebar empty state when no conversations exist | Done |
| FR-6.12: Inspector with usage section (tokens, cost, turns progress bar) and workspace section | Done |
| FR-6.13: Agent card Start button launches session and dismisses library | Done |
| FR-6.14: Inspector toggle button in toolbar (sidebar.trailing icon, ⌘⌥0) | Done |
| FR-6.15: Chat area expands to fill inspector space when inspector is hidden | Done |
| FR-6.16: Sidecar status pill in toolbar center with popover (status, URL, connect/stop/reconnect) | Done |
| FR-6.17: Sidebar bottom bar with Catalog, Agents, and New Session buttons | Done |
| FR-6.18: Chat header with tappable agent icon, mission preview, Fork/Rename in overflow menu | Done |
| FR-6.19: Settings reorganized: General / Connection (with live sidecar status) / Developer tabs | Done |
| FR-6.20: New Session sheet with recent agents row, collapsible options, mode tooltips | Done |
| FR-6.21: Agent Editor consolidated from 5 steps to 3 (Identity, Capabilities, System Prompt) | Done |

### FR-7: Blackboard

**Status:** Implemented (HTTP API + disk persistence)

| Requirement | Status |
|---|---|
| FR-7.1: In-memory key-value store | Done |
| FR-7.2: Persist to JSON on disk (~/.claudpeer/blackboard/) | Done |
| FR-7.3: HTTP POST /blackboard/write | Done |
| FR-7.4: HTTP GET /blackboard/read | Done |
| FR-7.5: HTTP GET /blackboard/query (glob pattern) | Done |
| FR-7.6: HTTP GET /blackboard/keys | Done |
| FR-7.7: HTTP GET /blackboard/health | Done |
| FR-7.8: CORS headers for localhost | Done |
| FR-7.9: Blackboard as custom SDK tools for agents (blackboard_read/write/query/subscribe) | Done |
| FR-7.10: blackboard.update events broadcast to Swift via WebSocket | Done |
| FR-7.11: Blackboard events persisted to SwiftData (BlackboardEntry upsert) | Done |

### FR-8: Agent Provisioning

**Status:** Implemented

| Requirement | Status |
|---|---|
| FR-8.1: Resolve skills by ID from SwiftData | Done |
| FR-8.2: Resolve MCP servers by ID from SwiftData | Done |
| FR-8.3: Resolve permission set by ID from SwiftData | Done |
| FR-8.4: Build system prompt with skills appended | Done |
| FR-8.5: Build allowed tools from permissions + PeerBus tools | Done |
| FR-8.6: Map MCP servers to SDK config (stdio/SSE) | Done |
| FR-8.7: Append GitHub repo context to system prompt | Done |
| FR-8.8: Append mission to system prompt | Done |
| FR-8.9: Working dir: explicit path override | Done |
| FR-8.10: Working dir: GitHub clone path | Done |
| FR-8.11: Working dir: agent default | Done |
| FR-8.12: Working dir: ephemeral sandbox fallback | Done |

### FR-9: Application Preferences (Settings)

**Status:** Implemented

Configurable application preferences accessible via Cmd+, (standard macOS Settings scene).

| Requirement | Status |
|---|---|
| FR-9.1: Three-tab settings window (General, Connection, Developer) | Done |
| FR-9.2: Appearance picker (System/Light/Dark) applied app-wide via preferredColorScheme | Done |
| FR-9.3: Default model picker (sonnet/opus/haiku) | Done |
| FR-9.4: Default max turns stepper (1-100) | Done |
| FR-9.5: Default max budget field | Done |
| FR-9.6: Auto-connect sidecar toggle | Done |
| FR-9.7: WebSocket port override (default 9849) | Done |
| FR-9.8: HTTP API port override (default 9850) | Done |
| FR-9.9: Bun path override with file picker | Done |
| FR-9.10: Sidecar project path override with folder picker | Done |
| FR-9.11: Data directory path with folder picker | Done |
| FR-9.12: Log level picker (debug/info/warning/error) | Done |
| FR-9.13: Reset All Settings button with confirmation | Done |
| FR-9.14: Open Data Directory in Finder button | Done |
| FR-9.15: Settings persisted via @AppStorage (UserDefaults) | Done |
| FR-9.16: SidecarManager accepts configured ports and path overrides from settings | Done |
| FR-9.17: Centralized AppSettings enum with all keys and defaults | Done |

### FR-10: Multi-Instance Support

**Status:** Implemented

Each app instance runs with fully isolated data, sidecar, and settings. Instances are identified by name via `--instance <name>` launch argument.

| Requirement | Status |
|---|---|
| FR-10.1: Parse `--instance <name>` from launch arguments (default: "default") | Done |
| FR-10.2: Namespace SwiftData store per instance (~/.claudpeer/instances/<name>/data/) | Done |
| FR-10.3: Namespace blackboard per instance (~/.claudpeer/instances/<name>/blackboard/) | Done |
| FR-10.4: Namespace sidecar logs per instance (~/.claudpeer/instances/<name>/logs/) | Done |
| FR-10.5: Per-instance UserDefaults suite (com.claudpeer.app.<name>) | Done |
| FR-10.6: Dynamic port allocation for non-default instances (avoids port collisions) | Done |
| FR-10.7: Default instance uses preferred ports from settings for backward compat | Done |
| FR-10.8: Pass CLAUDPEER_DATA_DIR env var to sidecar process | Done |
| FR-10.9: Sidecar blackboard reads CLAUDPEER_DATA_DIR for storage path | Done |
| FR-10.10: Window title shows instance name when not "default" | Done |
| FR-10.11: @AppStorage uses per-instance UserDefaults store across all views | Done |
| FR-10.12: DefaultsSeeder uses per-instance UserDefaults | Done |
| FR-10.13: All instance directories created on startup (ensureDirectories) | Done |

### FR-11: File Attachments

**Status:** Implemented

Users can attach images and documents (txt, md, pdf) to chat messages via the attach button, paste (images), or drag-and-drop.

| Requirement | Status |
|---|---|
| FR-11.1: Attach images (png, jpg, gif, webp) via file picker | Done |
| FR-11.2: Paste images from clipboard (Cmd+V) | Done |
| FR-11.3: Drag-and-drop images into chat input | Done |
| FR-11.4: Attach text files (.txt) via file picker or drag-and-drop | Done |
| FR-11.5: Attach markdown files (.md) via file picker or drag-and-drop | Done |
| FR-11.6: Attach PDF files (.pdf) via file picker or drag-and-drop | Done |
| FR-11.7: Image thumbnails in message bubbles (grid layout) | Done |
| FR-11.8: Document thumbnails with file icon, name, and size | Done |
| FR-11.9: Full-size image preview overlay (click to zoom) | Done |
| FR-11.10: Pending attachment strip above input (with remove buttons) | Done |
| FR-11.11: Images sent to Claude via temp files + Read tool instruction | Done |
| FR-11.12: Text/markdown files inlined directly in the prompt | Done |
| FR-11.13: PDF files sent to Claude via temp files + Read tool instruction | Done |
| FR-11.14: Attachment indicator in sidebar preview (photo/doc.text/paperclip icon) | Done |
| FR-11.15: Attachments stored on disk (~/.claudpeer/attachments/) | Done |
| FR-11.16: File size validation (5MB images, 10MB documents) | Done |
| FR-11.17: Wire protocol supports attachments with mediaType and fileName | Done |

### FR-12: Catalog System

**Status:** Implemented

Browsable catalog of pre-built agents (30), skills (101), and MCP servers (100) with one-click installation and cascading dependency resolution.

| Requirement | Status |
|---|---|
| FR-12.1: Directory-based catalog structure (agents/, skills/, mcps/ with index.json + per-item JSON/MD) | Done |
| FR-12.2: CatalogService singleton loads all items from bundled resources at startup | Done |
| FR-12.3: Agent catalog with 30 agents across categories (Core Team, Specialists, Content, Infrastructure) | Done |
| FR-12.4: Skill catalog with 101 skills across categories (Development, Testing, DevOps, etc.) | Done |
| FR-12.5: MCP catalog with 100 servers across categories (Developer Tools, Data, AI, Cloud, etc.) | Done |
| FR-12.6: Per-agent system prompts stored as .md files with identity, boundaries, collaboration rules | Done |
| FR-12.7: Per-skill content stored as .md files with methodology, procedures, and guidance | Done |
| FR-12.8: Find operations by catalogId for agents, skills, and MCPs | Done |
| FR-12.9: Category listing (sorted, deduplicated) for filtering UI | Done |
| FR-12.10: Install MCP from catalog (maps transport config, sets catalogId) | Done |
| FR-12.11: Install Skill from catalog (cascades required MCPs, resolves UUID references) | Done |
| FR-12.12: Install Agent from catalog (cascades skills + MCPs, copies system prompt, sets origin) | Done |
| FR-12.13: Idempotent install (re-installing returns existing SwiftData instance) | Done |
| FR-12.14: Uninstall agent/skill/MCP by catalogId (deletes from SwiftData) | Done |
| FR-12.15: Dependency resolution for agents (lists uninstalled skills + MCPs needed) | Done |
| FR-12.16: Dependency resolution for skills (lists uninstalled MCPs needed) | Done |
| FR-12.17: Installed status check by catalogId across all three types | Done |
| FR-12.18: CatalogBrowserView with tab-based navigation (Agents, Skills, MCPs) | Done |
| FR-12.19: Search and category filter in catalog browser | Done |
| FR-12.20: Catalog cards with icon, name, truncated description, category, tags, install status | Done |
| FR-12.21: Tap catalog card to open detail sheet | Done |
| FR-12.22: CatalogDetailView with full item information (header, chips, tags, description) | Done |
| FR-12.23: Agent detail shows resolved required skills and extra MCPs by name | Done |
| FR-12.24: Agent detail shows collapsible system prompt preview (DisclosureGroup) | Done |
| FR-12.25: Skill detail shows required MCPs, triggers (FlowLayout wrapping), and full content | Done |
| FR-12.26: MCP detail shows transport config (command/args for stdio, URL for http) and homepage link | Done |
| FR-12.27: Detail view footer with Install/Uninstall button and installed status badge | Done |
| FR-12.28: Install/uninstall from detail view refreshes catalog browser card status | Done |
| FR-12.29: Data integrity — all agent skill references and skill MCP references resolve | Done |
| FR-12.30: Catalog accessible from toolbar | Done |

### FR-13: Test Infrastructure

**Status:** Implemented

XCTest-based unit test target for verifying catalog system integrity, service logic, and app configuration.

| Requirement | Status |
|---|---|
| FR-13.1: ClaudPeerTests target in Xcode project with scheme integration | Done |
| FR-13.2: CatalogModelTests — JSON decoding for CatalogMCP, CatalogSkill, CatalogAgent | Done |
| FR-13.3: CatalogModelTests — CatalogItem enum case construction and extraction | Done |
| FR-13.4: CatalogServiceTests — catalog loading, counts, and emptiness checks | Done |
| FR-13.5: CatalogServiceTests — find operations and category listing | Done |
| FR-13.6: CatalogServiceTests — agent system prompts and skill content loaded from .md files | Done |
| FR-13.7: CatalogServiceTests — install/uninstall with in-memory SwiftData ModelContainer | Done |
| FR-13.8: CatalogServiceTests — cascading install (agent → skills → MCPs) | Done |
| FR-13.9: CatalogServiceTests — idempotent install returns same instance | Done |
| FR-13.10: CatalogServiceTests — dependency resolution excludes already-installed items | Done |
| FR-13.11: CatalogServiceTests — data integrity (unique IDs, valid cross-references, required fields) | Done |
| FR-13.12: InstanceConfigTests — directory structure, UserDefaults suite, port allocation | Done |
| FR-13.13: FileSystemServiceTests — directory listing, file reading, binary detection, icons, markdown detection | Done |
| FR-13.14: GitServiceTests — repo detection, status parsing, diff/diffCached/diffSummary, fullDiff | Done |
| FR-13.15: FileNodeTests — initialization, computed properties, loadChildren, reloadChildren, applyGitStatus | Done |
| FR-13.16: FileExplorerIntegrationTests — git path resolution, @Published behavior, edge cases, deep nesting | Done |
| FR-13.17: 154 tests passing with 0 failures | Done |

### FR-14: Inter-Agent Communication (PeerBus)

**Status:** Implemented

Full suite of PeerBus tools injected as in-process MCP server into every Agent SDK session.

| Requirement | Status |
|---|---|
| FR-14.1: ToolContext shared across all stores, broadcast, and spawnSession | Done |
| FR-14.2: PeerBus MCP server factory (createSdkMcpServer) injected into every session | Done |
| FR-14.3: blackboard_read — read entry by key | Done |
| FR-14.4: blackboard_write — write entry, emit blackboard.update event | Done |
| FR-14.5: blackboard_query — glob-pattern search | Done |
| FR-14.6: blackboard_subscribe — return current matches, note subscription | Done |
| FR-14.7: peer_send_message — async direct message to agent by name or session ID | Done |
| FR-14.8: peer_broadcast — broadcast to all active sessions on a named channel | Done |
| FR-14.9: peer_receive_messages — drain inbox for calling session | Done |
| FR-14.10: peer_list_agents — list all active sessions and registered definitions | Done |
| FR-14.11: peer_delegate_task — spawn/route task to target agent, optional blocking | Done |
| FR-14.12: peer_chat_start — create blocking conversation channel, wait for reply | Done |
| FR-14.13: peer_chat_reply — reply to channel, wait for next message | Done |
| FR-14.14: peer_chat_listen — block until incoming chat request | Done |
| FR-14.15: peer_chat_close — close channel, unblock all waiters | Done |
| FR-14.16: peer_chat_invite — add participant to existing channel | Done |
| FR-14.17: workspace_create — create shared directory under ~/.claudpeer/workspaces/ | Done |
| FR-14.18: workspace_join — join existing workspace, get path | Done |
| FR-14.19: workspace_list — list all workspaces with participant counts | Done |
| FR-14.20: ChatChannelStore with deadlock detection (circular wait prevention) | Done |
| FR-14.21: MessageStore with per-session inboxes and drain/peek | Done |
| FR-14.22: agent.register command — Swift sends agent definitions to sidecar on connect | Done |

### FR-15: Agent Comms View

**Status:** Implemented

Unified timeline UI for observing all inter-agent communication.

| Requirement | Status |
|---|---|
| FR-15.1: AgentCommsView with filter tabs (All/Chats/Delegations/Blackboard) | Done |
| FR-15.2: CommsTimelineEntry with event-specific icons, headers, and body | Done |
| FR-15.3: Agent Comms accessible from toolbar button | Done |
| FR-15.4: Events sourced from AppState.commsEvents (populated by sidecar events) | Done |
| FR-15.5: Sidebar conversation tree with parent-child nesting (DisclosureGroup) | Done |
| FR-15.6: Type-specific conversation icons (delegation, agent-to-agent, user+agent, group) | Done |
| FR-15.7: Root conversations filtered to exclude children from top-level lists | Done |

### FR-16: Built-in Ecosystem Seeding

**Status:** Implemented

First-launch seeding of default agents, skills, MCP servers, permission presets, and system prompt templates into SwiftData.

| Requirement | Status |
|---|---|
| FR-16.1: DefaultsSeeder seeds 5 permission presets from DefaultPermissionPresets.json | Done |
| FR-16.2: DefaultsSeeder seeds 4 MCP servers from DefaultMCPs.json (Argus, AppXray, GitHub, Sentry) | Done |
| FR-16.3: DefaultsSeeder seeds 5 ClaudPeer skills from DefaultSkills/*/SKILL.md with frontmatter parsing | Done |
| FR-16.4: DefaultsSeeder seeds 7 built-in agents from DefaultAgents/*.json | Done |
| FR-16.5: Agent seeding resolves skill references by name → UUID linking | Done |
| FR-16.6: Agent seeding resolves MCP server references by name → UUID linking | Done |
| FR-16.7: Agent seeding resolves permission preset by name → UUID linking | Done |
| FR-16.8: System prompt templates loaded from SystemPromptTemplates/*.md (specialist, worker, coordinator) | Done |
| FR-16.9: Template variable resolution ({{role}}, {{domain}}, {{constraints}}, {{team_description}}, {{pipeline_style}}) | Done |
| FR-16.10: Seeded agents marked with origin: .builtin | Done |
| FR-16.11: Seeded skills marked with source: .builtin | Done |
| FR-16.12: Seeding is idempotent (UserDefaults flag + permission count check) | Done |
| FR-16.13: All 30 catalog agents include PeerBus system skills in requiredSkills | Done |
| FR-16.14: Catalog agent install cascades PeerBus skills alongside domain skills | Done |

### FR-17: Inspector File Explorer

**Status:** Implemented

File tree browser in the Inspector pane showing the agent's working directory with syntax-highlighted source viewing, markdown preview, and git diff support.

| Requirement | Status |
|---|---|
| FR-17.1: Inspector tab picker (Info / Files) when session has a working directory | Done |
| FR-17.2: File tree with lazy-loaded directory expansion (DisclosureGroup) | Done |
| FR-17.3: Sorted listing (directories first, then alphabetical) | Done |
| FR-17.4: Common directories excluded by default (.git, node_modules, DerivedData, etc.) | Done |
| FR-17.5: Show/hide hidden files toggle | Done |
| FR-17.6: "Changes Only" filter to show only git-modified files | Done |
| FR-17.7: Git status badges on files (colored dots: modified/added/deleted/renamed/untracked) | Done |
| FR-17.8: Directory change indicators (dim dot when any descendant has changes) | Done |
| FR-17.9: File icons by extension (SF Symbols for swift, ts, py, json, md, etc.) | Done |
| FR-17.10: File content viewer with back navigation | Done |
| FR-17.11: Syntax highlighting via Highlightr (highlight.js) with github/github-dark themes | Done |
| FR-17.12: Line numbers in source view (gutter with separator) | Done |
| FR-17.13: Markdown preview mode for .md files (rendered via MarkdownUI) | Done |
| FR-17.14: Git diff view with colored +/- lines (green added, red removed, blue hunk headers) | Done |
| FR-17.15: Diff summary showing +added/-removed line counts | Done |
| FR-17.16: Mode picker (Preview/Source/Diff) with context-aware available modes | Done |
| FR-17.17: Binary file detection with "Open in Default App" fallback | Done |
| FR-17.18: File metadata display (size, extension, modification date) | Done |
| FR-17.19: Action bar (Open in Editor, Copy Path) | Done |
| FR-17.20: Auto-refresh on agent file-modifying tool calls (fileTreeRefreshTrigger) | Done |
| FR-17.21: Manual refresh button in toolbar | Done |
| FR-17.22: Abbreviated path display in toolbar with full path tooltip | Done |
| FR-17.23: Settings menu (show hidden, changes only, Reveal in Finder, Open in Terminal) | Done |
| FR-17.24: Git path resolved dynamically (/usr/bin, /opt/homebrew, /usr/local) | Done |
| FR-17.25: Async I/O — git operations run off main thread via Task.detached | Done |
| FR-17.26: Highlightr cached in coordinator, skips re-highlight when inputs unchanged | Done |
| FR-17.27: DiffTextView uses NSTextView for scalable rendering of large diffs | Done |
| FR-17.28: FileNode @MainActor with nonisolated init for Swift 6 concurrency safety | Done |
| FR-17.29: FileContentView reloads on file change (.onChange of node.id) | Done |
| FR-17.30: Code blocks in chat upgraded to use Highlightr syntax highlighting | Done |

### FR-18: File Explorer Services

**Status:** Implemented

Backend services supporting the file explorer.

| Requirement | Status |
|---|---|
| FR-18.1: FileSystemService — directory listing, file reading (512KB cap), binary detection | Done |
| FR-18.2: GitService — git status parsing (porcelain), diff, diffCached, diffSummary | Done |
| FR-18.3: GitService — rename detection, quoted path unescaping | Done |
| FR-18.4: FileNode model — ObservableObject with lazy children, @Published gitStatus | Done |
| FR-18.5: FileNode.applyGitStatus — recursive status propagation from root | Done |
| FR-18.6: FileNode.hasChanges — computed property traversing children | Done |

---

## 3. User Stories

### US-1: Create and Configure an Agent
**As a** developer, **I want to** create a reusable agent template with specific skills and permissions, **so that** I can quickly launch configured Claude sessions for different tasks.

**Acceptance criteria:**
- [x] Can create agent with name, description, system prompt
- [x] Can select model, set turn/budget limits
- [x] Can assign skills, MCPs, permissions from pools
- [x] Can set working directory and GitHub repo
- [x] Agent persists across app restarts

### US-2: Start a Conversation
**As a** developer, **I want to** start a chat with an agent, **so that** I can get AI assistance with my coding tasks.

**Acceptance criteria:**
- [x] Can select an agent and start a new conversation
- [x] Can provide a mission/goal for the session
- [x] Messages stream in real-time
- [x] Tool calls are visible in the chat
- [x] Session cost is tracked

### US-3: Resume a Previous Session
**As a** developer, **I want to** continue a paused conversation, **so that** I don't lose context from previous interactions.

**Acceptance criteria:**
- [x] Conversations persist in sidebar
- [x] Can resume session with full Claude context (via session ID)
- [x] Can view historical messages without resuming

### US-4: Manage Multiple Sessions
**As a** developer, **I want to** run multiple agent sessions simultaneously, **so that** I can work on different tasks in parallel.

**Acceptance criteria:**
- [x] Sidebar shows all conversations
- [x] Can switch between conversations
- [x] Multiple sessions can stream concurrently
- [x] Inspector shows metadata for selected conversation

### US-5: Use Blackboard for External Integration
**As a** developer, **I want to** read/write structured data via HTTP, **so that** scripts and tools can exchange information with agents.

**Acceptance criteria:**
- [x] HTTP API on localhost:9850
- [x] Write, read, query, list keys operations
- [x] Data persists to disk
- [x] Health check endpoint available

### US-6: Manage Conversations
**As a** developer, **I want to** organize my conversations by renaming, pinning, closing, and deleting them, **so that** I can keep my workspace clean and quickly find important sessions.

**Acceptance criteria:**
- [x] Can rename conversations via context menu, chat header, or inspector
- [x] Can pin/unpin conversations to keep them at the top
- [x] Can close active sessions from sidebar, header, or inspector
- [x] Can delete conversations with confirmation
- [x] Can duplicate conversations with their agent config
- [x] Conversations auto-name from first message text

### US-7: Start a Session with Options
**As a** developer, **I want to** choose an agent, model, mode, mission, and working directory when starting a session, **so that** I can configure each session for its specific task.

**Acceptance criteria:**
- [x] New Session sheet (Cmd+N) with agent grid picker
- [x] Model override dropdown
- [x] Session mode selector (interactive/autonomous/worker)
- [x] Optional mission text field
- [x] Working directory picker with folder browser
- [x] Quick Chat shortcut (Cmd+Shift+N) for freeform sessions

### US-8: Configure Application Preferences
**As a** developer, **I want to** customize the app appearance, default model, and sidecar connection settings, **so that** I can tailor ClaudPeer to my environment and preferences.

**Acceptance criteria:**
- [x] Can switch between System, Light, and Dark appearance
- [x] Appearance change applies immediately to all windows
- [x] Can set default model, max turns, and budget for new sessions
- [x] Can override WebSocket/HTTP ports for sidecar
- [x] Can override Bun and sidecar paths with file/folder pickers
- [x] Can toggle auto-connect on launch
- [x] Can reset all settings to defaults
- [x] Settings persist across app restarts

### US-9: Attach Files to Chat Messages
**As a** developer, **I want to** attach images and documents (txt, md, pdf) to my chat messages, **so that** I can share context with Claude and get help with files I'm working on.

**Acceptance criteria:**
- [x] Can attach files via paperclip button (images + txt/md/pdf)
- [x] Can paste images from clipboard with Cmd+V
- [x] Can drag-and-drop files onto the chat input area
- [x] Pending attachments appear as thumbnails above the input field
- [x] Image attachments display as thumbnails in sent messages (clickable for full-size preview)
- [x] Document attachments display with file icon, name, and file size
- [x] Text/markdown file contents are inlined directly into the prompt sent to Claude
- [x] Image and PDF files are saved to temp directory and Claude reads them via its Read tool
- [x] Sidebar shows appropriate icon (photo/doc.text/paperclip) when the last message has attachments

### US-10: Run Multiple Isolated Instances
**As a** developer, **I want to** run multiple ClaudPeer instances simultaneously with separate data, **so that** I can have isolated agent workspaces per project.

**Acceptance criteria:**
- [x] Can launch a named instance via `open -n ClaudPeer.app --args --instance my-project`
- [x] Each instance has its own SwiftData store, blackboard, logs, and UserDefaults
- [x] Non-default instances allocate dynamic ports to avoid collisions
- [x] Window title shows instance name for disambiguation
- [x] Default instance (no flag) is backward compatible with existing behavior
- [x] Settings changes in one instance do not affect other instances

### US-11: Browse and Install from Catalog
**As a** developer, **I want to** browse a curated catalog of agents, skills, and MCP servers and install them with one click, **so that** I can quickly assemble powerful agent configurations without manual setup.

**Acceptance criteria:**
- [x] Can open the catalog browser from the toolbar
- [x] Can browse agents, skills, and MCPs in separate tabs
- [x] Can search by name and filter by category
- [x] Cards show key info (icon, name, description, tags, install status)
- [x] Tapping a card opens a detail sheet with full information
- [x] Agent details show required skills, extra MCPs, and system prompt preview
- [x] Skill details show required MCPs, triggers, and full content markdown
- [x] MCP details show transport configuration and homepage link
- [x] Can install/uninstall items from the detail view
- [x] Installing an agent cascades to install its required skills and MCPs
- [x] Installing a skill cascades to install its required MCPs
- [x] Install/uninstall status updates immediately in the catalog browser

### US-12: Agent-to-Agent Collaboration
**As a** developer, **I want** my agents to communicate with each other, share findings on a blackboard, and delegate tasks, **so that** complex multi-step workflows can be handled by a team of specialist agents.

**Acceptance criteria:**
- [x] Every agent session has PeerBus tools available (blackboard, messaging, chat, delegation, workspace)
- [x] Agents can send async messages to each other (peer_send_message, peer_broadcast)
- [x] Agents can start blocking back-and-forth conversations (peer_chat_start/reply/close)
- [x] Agents can delegate tasks to other agents by name (peer_delegate_task)
- [x] Agents can read/write structured data on the blackboard (blackboard_read/write/query)
- [x] Agents can create and join shared workspaces (workspace_create/join/list)
- [x] Deadlock detection prevents circular blocking waits between agents
- [x] Agent definitions are registered with the sidecar on connect for delegation lookup

### US-13: View Inter-Agent Communication
**As a** developer, **I want** to see all inter-agent messages, delegations, and blackboard updates in a unified timeline, **so that** I can observe how agents collaborate and debug their interactions.

**Acceptance criteria:**
- [x] Agent Comms view accessible from toolbar
- [x] Filter tabs: All, Chats, Delegations, Blackboard
- [x] Each event shows icon, participants, message/task text, and timestamp
- [x] Peer chat events, delegation events, and blackboard updates all appear in timeline
- [x] Sidebar shows parent-child conversation nesting (delegated conversations nested under parents)
- [x] Type-specific icons distinguish user+agent, agent-to-agent, delegation, and group conversations

### US-15: Ready-to-Use Agent Team on First Launch
**As a** developer, **I want** ClaudPeer to come with a pre-configured team of agents (Orchestrator, Coder, Reviewer, Researcher, Tester, DevOps, Writer) with PeerBus skills and permission presets already wired, **so that** I can start multi-agent workflows immediately without manual setup.

**Acceptance criteria:**
- [x] First launch seeds 7 agents, 5 skills, 4 MCP servers, 5 permission presets
- [x] Agents are pre-linked to their skills, MCPs, and permissions
- [x] System prompts are generated from templates with role-specific variables
- [x] Seeded agents have PeerBus tools available via their skills
- [x] Users can modify or delete any seeded content
- [x] All 30 catalog agents include PeerBus system skills for install-time linking

### US-16: Browse Agent Working Directory Files
**As a** developer, **I want to** browse the files in my agent's working directory, view source code with syntax highlighting, preview markdown files, and see git diffs, **so that** I can understand what the agent is working on without leaving ClaudPeer.

**Acceptance criteria:**
- [x] Inspector pane has Info / Files tabs when session has a working directory
- [x] File tree shows directories and files with appropriate icons
- [x] Expanding a directory lazily loads its children
- [x] Git-modified files show colored status badges (orange=modified, green=added, red=deleted)
- [x] Can filter to show only changed files
- [x] Clicking a file shows its content with syntax highlighting
- [x] Markdown files have a rendered preview mode
- [x] Git-changed files have a diff view with colored +/- lines
- [x] File tree auto-refreshes when agent modifies files (tool calls)
- [x] Can open files in default editor or copy path to clipboard
- [x] Can reveal working directory in Finder or open in Terminal

### US-14: Read Rich Markdown Responses
**As a** developer, **I want to** see Claude's responses rendered with proper markdown formatting, **so that** code blocks, links, headers, and lists are easy to read and interact with.

**Acceptance criteria:**
- [x] Agent messages render headings, lists, bold, italic, blockquotes, tables
- [x] Code blocks display with language label and monospaced font
- [x] Code blocks have a Copy button that copies contents to clipboard
- [x] Links are clickable and open in the default browser
- [x] User messages remain plain text (not rendered as markdown)
- [x] Streaming text appears live as it arrives (not just animated dots)
- [x] Can copy any message via hover copy button

---

## 4. User Flows

### Flow 1: App Launch → New Session

```mermaid
flowchart TD
    Launch([App launches]) --> Boot["Start sidecar process"]
    Boot --> WS["Connect WebSocket"]
    WS --> Ready["Status: Connected"]
    Ready --> CmdN["User presses Cmd+N"]
    CmdN --> Sheet["New Session sheet opens"]
    Sheet --> Pick{"Pick agent or Freeform?"}
    Pick -->|Agent| SelectAgent["Select agent card\nOptions auto-fill from defaults"]
    Pick -->|Freeform| Freeform["No agent selected\nModel defaults to sonnet"]
    SelectAgent --> Customize["Configure: model, mode,\nmission, working directory"]
    Freeform --> Customize
    Customize --> StartBtn["Click Start Session"]
    StartBtn --> Provision["AgentProvisioner builds config\nCreate Session + Conversation"]
    Provision --> Type["User types first message"]
    Type --> AutoName["Topic auto-set from message\ne.g. 'Coder: Fix the login...'"]
    AutoName --> Stream["Agent SDK query starts\nTokens stream back"]
    Stream --> Display["Chat displays streaming response\nTool calls shown inline"]
```

### Flow 2: Resume Conversation

```mermaid
flowchart TD
    Open([App opens]) --> Sidebar["Sidebar loads conversations\nfrom SwiftData"]
    Sidebar --> Click["User clicks paused conversation"]
    Click --> Check{"Has claudeSessionId?"}
    Check -->|Yes| Resume["session.resume → sidecar\nFull context restored"]
    Check -->|No| ReadOnly["Show historical messages"]
    Resume --> Chat["User continues chatting"]
```

### Flow 3: Manage Conversations

```mermaid
flowchart TD
    RightClick(["Right-click conversation\nin sidebar"]) --> Menu["Context menu appears"]
    Menu -->|Rename| RenamePopover["Text field alert\nEdit topic, press Enter"]
    Menu -->|Pin| TogglePin["Toggle isPinned\nMove to/from Pinned section"]
    Menu -->|Close| CloseConvo["Set status = closed\nSend sessionPause to sidecar\nMove to Recent section"]
    Menu -->|Delete| Confirm["Confirmation alert"]
    Confirm -->|Confirm| DeleteConvo["Delete from SwiftData"]
    Confirm -->|Cancel| Dismiss["Dismiss alert"]
    Menu -->|Duplicate| DupeConvo["Copy agent config\ninto new Conversation"]
```

### Flow 4: Configure Settings

```mermaid
flowchart TD
    Open([User presses Cmd+,]) --> Settings["Settings window opens"]
    Settings --> Tabs{"Select tab"}
    Tabs -->|General| General["Appearance picker\nDefault model/turns/budget"]
    Tabs -->|Connection| Connection["Live sidecar status + actions\nAuto-connect toggle\nWS/HTTP port fields"]
    Tabs -->|Developer| Developer["Bun path + Sidecar path overrides\nData directory + Browse\nLog level picker\nReset All / Open Data Dir"]
    General --> Apply["Changes saved to UserDefaults\nApplied immediately"]
    Connection --> Apply
    Advanced --> Apply
    Apply --> Reconnect{"Port or path changed?"}
    Reconnect -->|Yes| Restart["Reconnect sidecar\nwith new config"]
    Reconnect -->|No| Done([Done])
    Restart --> Done
```

### Flow 5: Read a Markdown Response

```mermaid
flowchart TD
    Send([User sends message]) --> Stream["Sidecar streams tokens"]
    Stream --> Live["Live streaming bubble shows\ntext as it arrives with\nMarkdownUI rendering"]
    Live --> Complete["Response complete\nSaved as ConversationMessage"]
    Complete --> Render["MarkdownContent renders:\nheadings, lists, code blocks,\nlinks, images, tables"]
    Render --> Interact{"User interaction?"}
    Interact -->|Click link| Browser["Opens in default browser"]
    Interact -->|Copy code| Clipboard["Code copied to clipboard\nButton shows checkmark"]
    Interact -->|Hover message| Actions["Copy button + timestamp revealed"]
    Interact -->|Copy message| CopyAll["Full message text\ncopied to clipboard"]
```

### Flow 6: Agent-to-Agent Delegation

```mermaid
flowchart TD
    Trigger([Agent A calls\npeer_delegate_task]) --> Lookup["PeerBus looks up target\nagent definition by name"]
    Lookup --> Found{"Agent definition\nregistered?"}
    Found -->|No| Inbox["Route to existing session's\ninbox as urgent message"]
    Found -->|Yes| Policy{"Instance policy?"}
    Policy -->|spawn| Spawn["spawnAutonomous()\nnew session + config"]
    Policy -->|singleton| Queue["Push to existing\nsingleton's inbox"]
    Policy -->|pool| Pool["Find idle or spawn\n(up to max)"]
    Spawn --> Wait{"wait_for_result?"}
    Wait -->|true| Block["Block tool call until\ndelegate session.result"]
    Wait -->|false| Return["Return immediately\nwith sessionId"]
    Block --> Result["Return delegate's\nresult text"]
    Inbox --> Done([Delegation complete])
    Queue --> Done
    Pool --> Wait
    Result --> Done
    Return --> Done
```

### Flow 7: Launch Named Instance

```mermaid
flowchart TD
    Launch(["open -n ClaudPeer.app\n--args --instance project-a"]) --> Parse["InstanceConfig parses\n--instance 'project-a'"]
    Parse --> Dirs["Ensure directories:\n~/.claudpeer/instances/project-a/\ndata/ blackboard/ logs/"]
    Dirs --> Store["ModelContainer uses\nproject-a/data/ClaudPeer.store"]
    Store --> Defaults["UserDefaults suite:\ncom.claudpeer.app.project-a"]
    Defaults --> Seed["DefaultsSeeder checks\nper-instance seeded flag"]
    Seed --> Ports["Allocate free ports\n(dynamic, not 9849/9850)"]
    Ports --> Sidecar["Launch sidecar with:\nCLAUDPEER_WS_PORT=<dynamic>\nCLAUDPEER_HTTP_PORT=<dynamic>\nCLAUDPEER_DATA_DIR=...project-a"]
    Sidecar --> Title["Window title:\n'ClaudPeer — project-a'"]
    Title --> Ready([Fully isolated instance])
```

### Flow 8: Attach Files to a Message

```mermaid
flowchart TD
    Start([User in chat]) --> Method{"Attach method?"}
    Method -->|Paperclip button| FilePicker["File picker opens\nSupports: png, jpg, gif, webp,\ntxt, md, pdf"]
    Method -->|Cmd+V| Paste["Image pasted from clipboard\n(Custom NSTextField intercepts)"]
    Method -->|Drag-and-drop| Drop["File dropped on input area\nValidated by extension"]
    FilePicker --> Pending["File added to\npending attachment strip"]
    Paste --> Pending
    Drop --> Pending
    Pending --> Preview{"File type?"}
    Preview -->|Image| ImgThumb["Image thumbnail 60x60"]
    Preview -->|Document| DocThumb["File icon + name"]
    ImgThumb --> Send["User clicks Send"]
    DocThumb --> Send
    Send --> Save["Attachment saved to disk\n~/.claudpeer/attachments/"]
    Save --> Wire["WireAttachment sent to sidecar\n(base64 + mediaType + fileName)"]
    Wire --> Route{"Sidecar routes\nby mediaType?"}
    Route -->|text/plain, text/markdown| Inline["Content decoded to UTF-8\nInlined directly in prompt"]
    Route -->|image/*, application/pdf| TempFile["Written to temp file\nPrompt says 'Read with Read tool'"]
    Inline --> Claude["Claude processes message"]
    TempFile --> Claude
    Claude --> Response["Response streamed back"]
```

### Flow 9: Browse Catalog and Install Agent

```mermaid
flowchart TD
    Open([User clicks Catalog\nin toolbar]) --> Browser["CatalogBrowserView opens\nTabs: Agents / Skills / MCPs"]
    Browser --> Search["Optional: search by name\nor filter by category"]
    Search --> Tap["User taps agent card"]
    Tap --> Detail["CatalogDetailView sheet opens\nFull description, skills, MCPs,\nsystem prompt preview"]
    Detail --> Install{"Click Install?"}
    Install -->|Yes| Resolve["CatalogService resolves\ndependencies"]
    Resolve --> Cascade["Auto-install required skills\nAuto-install required MCPs"]
    Cascade --> Create["Agent created in SwiftData\nwith catalogId, system prompt,\nskill/MCP UUID references"]
    Create --> Refresh["Detail shows 'Installed'\nBrowser card updates badge"]
    Install -->|No| Close["Dismiss sheet"]
```

### Flow 10: Install Skill with MCP Dependencies

```mermaid
flowchart TD
    Tab([User switches to\nSkills tab]) --> Browse["Browse 101 skills\nacross categories"]
    Browse --> Tap["User taps skill card"]
    Tap --> Detail["Skill detail:\nrequired MCPs, triggers,\nfull content markdown"]
    Detail --> Install["Click Install"]
    Install --> MCPs["CatalogService installs\neach required MCP first"]
    MCPs --> Skill["Skill created in SwiftData\nwith mcpServerIds resolved"]
    Skill --> Done["Skill available for\nassignment to agents"]
```

### Flow 11: Browse Agent Files in Inspector

```mermaid
flowchart TD
    Select([User selects conversation\nwith working directory]) --> Tab["Inspector shows\nInfo / Files tabs"]
    Tab --> Click["User clicks Files tab"]
    Click --> Tree["File tree loads from\nworking directory"]
    Tree --> Git{"Is git repo?"}
    Git -->|Yes| Status["git status --porcelain\nGit badges shown on files"]
    Git -->|No| NoGit["Plain file tree\nno badges"]
    Status --> Browse["User browses tree\nexpands directories"]
    NoGit --> Browse
    Browse --> SelectFile["User clicks a file"]
    SelectFile --> Type{"File type?"}
    Type -->|Markdown| Preview["Markdown preview rendered\nvia MarkdownUI"]
    Type -->|Source code| Highlight["Syntax-highlighted source\nwith line numbers"]
    Type -->|Binary| Binary["Binary placeholder\n'Open in Default App' button"]
    Preview --> Mode["Mode picker: Preview / Source / Diff"]
    Highlight --> Mode
    Mode -->|Switch to Diff| Diff["Colored unified diff\n+added / -removed lines"]
    Mode -->|Back| Browse
    Diff --> Back["Back button returns\nto file tree"]
```

---

## 5. Non-Functional Requirements

| Requirement | Target | Status |
|---|---|---|
| macOS version | 14.0+ (Sonoma) | Met |
| Swift version | 6.0 (strict concurrency) | Met |
| Startup time | Sidecar ready within 1s | Met (~500ms) |
| Reconnect | Auto-reconnect within 5s | Met |
| Persistence | SwiftData (local, CloudKit-ready) | Met |
| Memory | Graceful with 10+ concurrent sessions | Untested |
| Security | Hardened runtime, localhost-only sidecar | Met |
| Multi-instance | Fully isolated data, ports, settings | Met |
| Test coverage | Unit tests for catalog, config, data integrity, file explorer | Met (131 Swift + 96 sidecar) |
| Catalog size | 30 agents + 101 skills + 100 MCPs bundled | Met |

---

## 6. Change Log

| Date | Change | Affected |
|---|---|---|
| 2026-03-21 | Lightweight ChatHandler for simple sessions: routes sessions without tools/MCPs/skills to `claude --print` instead of full Agent SDK. Response polling in Swift saves agent replies to SwiftData. Fixed AgentLibrary sheet presentation, added indigo/gray agent colors, built-in agent loading. | FR-2.10, FR-2.14, FR-3.15-3.17, Flow 6 |
| 2026-03-21 | Rich markdown chat: MarkdownUI rendering for agent messages, code blocks with copy button, live streaming text, hover copy/timestamp, clickable links. Settings screen: three-tab preferences (General/Connection/Advanced) with dark mode, port/path overrides, reset. SidecarManager accepts configurable settings. | FR-5.18-5.25, FR-9, US-8, US-9, Flow 4, Flow 5 |
| 2026-03-21 | UX improvements: smart naming, conversation management (rename/pin/close/delete/duplicate), New Session sheet, sidebar polish (timestamps, previews, pinned section, empty state, agent icons, swipe actions), chat header enhancements (rename, close/resume, clear, model pill, cost), inspector actions (pause/resume/stop, editable topic, open in editor), agent card Start button | FR-5, FR-6, US-6, US-7, Flow 1, Flow 3 |
| 2026-03-21 | File attachments: added txt/md/pdf support alongside images. Text/markdown files inlined in prompt, images/PDFs via temp files. Generalized wire protocol from WireImageAttachment to WireAttachment. Document thumbnails with icon+name+size. Sidebar shows context-aware attachment icons. | FR-5.9, FR-10, US-9, Flow 7 |
| 2026-03-21 | Multi-instance support: InstanceConfig parses `--instance <name>`, namespaces SwiftData/blackboard/logs/UserDefaults per instance, dynamic port allocation for non-default instances, CLAUDPEER_DATA_DIR env var for sidecar, window title with instance name. | FR-10, US-10, Flow 7, NFR |
| 2026-03-21 | Catalog system: directory-based catalog with 30 agents, 101 skills, 100 MCPs. CatalogService with loading, find, install/uninstall, cascading dependency resolution. CatalogBrowserView with tabs, search, category filter. CatalogDetailView with full item information, collapsible system prompt, FlowLayout triggers, install/uninstall actions. Per-agent .md system prompts. Agent → Skill → MCP hierarchy. | FR-2.15-2.18, FR-12, US-11, Flow 9, Flow 10 |
| 2026-03-21 | Test infrastructure: ClaudPeerTests XCTest target with 61 tests covering catalog model decoding, service operations (install/uninstall/cascading/idempotent/dependency resolution), data integrity (unique IDs, valid cross-references), InstanceConfig (directories, UserDefaults, ports). Fixed catalog skill ID case mismatches across 20 agent files. Added InstanceConfig.swift to project, fixed Swift 6 concurrency warning in AppSettings. | FR-13, NFR |
| 2026-03-21 | Initial spec created from implemented codebase | All sections |
| 2026-03-21 | Phase 4: Inter-Agent Communication. Full PeerBus tool suite (17 tools) implemented as in-process MCP server injected into every Agent SDK session. Tools: blackboard_read/write/query/subscribe, peer_send_message/broadcast/receive_messages/list_agents/delegate_task, peer_chat_start/reply/listen/close/invite, workspace_create/join/list. New stores: MessageStore, ChatChannelStore (with deadlock detection), WorkspaceStore. Refactored sidecar: shared ToolContext, SessionManager accepts injected registry and context, WsServer accepts injected dependencies, agent.register command. Swift: AppState handles all peer/blackboard events, persists to SwiftData, registers agent definitions on connect. New AgentCommsView with filter tabs. Sidebar enhanced with parent-child conversation nesting and type-specific icons. Removed stale ChatHandler references from FR-3 and Flow 6. | FR-3.15-3.18, FR-4.8, FR-7.9-7.11, FR-14, FR-15, US-12, US-13, Flow 6 |
| 2026-03-22 | Phase 4.5: Built-in Ecosystem. Full first-launch seeding: DefaultsSeeder expanded from permissions-only to 5 categories (permissions, MCPs, skills, agents, templates). Created 3 system prompt templates (specialist.md, worker.md, coordinator.md) with variable resolution. Agent seeding resolves cross-entity references by name (skills, MCPs, permissions). All 30 catalog agents updated with PeerBus system skills (peer-collaboration, blackboard-patterns, agent-identity) in requiredSkills — every agent in ClaudPeer knows how to collaborate via PeerBus. 131 Swift tests + 96 sidecar tests passing. | FR-16, US-15 |
| 2026-03-22 | Phase 6: UX Redesign + Inspector Toggle. Comprehensive UX overhaul: Settings reorganized into General/Connection (with live sidecar status and action buttons)/Developer tabs. Sidebar toolbar replaced with bottom bar (Catalog, Agents, + buttons). Main toolbar simplified to New Session + Quick Chat + status pill + inspector toggle. Chat header: tappable agent icon opens library, mission preview, Fork/Rename moved to overflow menu. Inspector transformed into monitoring dashboard with usage section (tokens, cost, turns progress bar), workspace section with Open in Terminal, and removed duplicate controls. New Session sheet: recent agents row, collapsible options DisclosureGroup, "Inherit from Agent" model default, mode tooltips. Agent Editor consolidated from 5 steps to 3 (Identity, Capabilities with Skills/MCPs/Permissions DisclosureGroups, System Prompt). Inspector toggle: toolbar button (sidebar.trailing, ⌘⌥0) shows/hides right inspector pane; chat expands to fill freed space via 2-column NavigationSplitView + HStack layout. Fixed macOS state restoration crash (WorkingDirectoryPicker environment object). Fixed FileNode Swift 6 concurrency (nonisolated init, @unchecked Sendable). | FR-6.14-6.21, FR-9.1, US-7, US-8, Flow 4 |
| 2026-03-22 | Phase 5: Inspector File Explorer. Tabbed Inspector (Info/Files) with file tree browser for agent working directories. FileSystemService, GitService, FileNode model. FileTreeView with DisclosureGroup, git badges, changes-only filter. FileContentView with three modes: Markdown preview, syntax-highlighted source (Highlightr), git diff (NSTextView). Async I/O, auto-refresh on tool calls, HighlightedCodeView for chat code blocks, dynamic git path, full a11y identifiers. | FR-17, FR-18, US-16, Flow 11 |
