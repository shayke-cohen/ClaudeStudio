# ClaudeStudio

A native macOS developer tool for orchestrating multiple Claude AI agent sessions. Agents chat with users and with each other, share knowledge through a blackboard, collaborate on files through shared workspaces, and discover each other across the local network.

![ClaudeStudio](docs/welcome-screen.png)

## Architecture

ClaudeStudio is a **two-process** app:

```
┌─────────────────────────────────┐     WebSocket (JSON)     ┌─────────────────────────────────┐
│     Swift macOS App             │◄────────────────────────►│     TypeScript Sidecar           │
│                                 │      localhost:9849       │                                 │
│  • SwiftUI + SwiftData          │                          │  • Bun runtime                   │
│  • UI, persistence, P2P         │                          │  • Claude Agent SDK sessions     │
│  • Agent provisioning           │                          │  • Blackboard (HTTP + disk)      │
│  • Conversation model           │                          │  • PeerBus tools + Task Board    │
└─────────────────────────────────┘                          └─────────────────────────────────┘
```

**Why two processes?** The Claude Agent SDK is TypeScript-only. The Swift app owns the UI and persistence (what SwiftUI/SwiftData do best), while the sidecar owns AI sessions and agent orchestration (what the SDK does best).

### Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| AI interface | Claude Agent SDK (TypeScript) | Persistent sessions, hooks, custom tools, native subagents |
| Sidecar runtime | Bun | Fast startup, TypeScript-native, single binary |
| App ↔ Sidecar | WebSocket on localhost | Low-latency, bidirectional streaming |
| Persistence | SwiftData | Modern, CloudKit sync potential, Swift-native |
| Concurrency | Swift 6 strict concurrency | `@MainActor` app state, `AsyncStream` for events |

## Project Structure

```
ClaudeStudio/
├── ClaudeStudio.xcodeproj           # Xcode project
├── project.yml                   # XcodeGen spec (macOS 14+, Swift 6)
├── system-plan-vision.md         # Full architecture vision & roadmap
│
├── ClaudeStudio/                    # Swift macOS App
│   ├── App/
│   │   ├── ClaudeStudioApp.swift    # @main, WindowGroup, model container
│   │   ├── AppState.swift        # Global state: sidecar status, selections, streaming
│   │   └── Log.swift             # Centralized OSLog logger with categories
│   ├── Models/                   # SwiftData @Model types
│   │   ├── Agent.swift           # Agent template (skills, MCPs, permissions, instance policy)
│   │   ├── Session.swift         # Running agent instance (status, mode, workspace)
│   │   ├── Conversation.swift    # Unified conversation (user↔agent and agent↔agent)
│   │   ├── ConversationMessage.swift
│   │   ├── Participant.swift     # .user or .agentSession
│   │   ├── Skill.swift           # Managed skill in pool
│   │   ├── MCPServer.swift       # MCP server config (.stdio or .http)
│   │   ├── PermissionSet.swift   # Reusable permission presets
│   │   ├── SharedWorkspace.swift # Shared directory for multi-agent collaboration
│   │   ├── BlackboardEntry.swift # Key-value knowledge store entry
│   │   ├── Peer.swift            # Discovered network peer
│   │   ├── TaskItem.swift        # Task board item (status, priority, lifecycle)
│   │   └── UnifiedLogEntry.swift # Normalized log entry (Swift + sidecar)
│   ├── Services/
│   │   ├── SidecarManager.swift  # Launch Bun, WebSocket client, reconnect
│   │   ├── SidecarProtocol.swift # Wire types: commands, events, AgentConfig
│   │   ├── AgentProvisioner.swift# Compose AgentConfig from SwiftData models
│   │   ├── GroupPromptBuilder.swift   # Group transcript + user-line prompts; peer-notify text
│   │   ├── GroupPeerFanOutContext.swift # Budget/dedup for automatic peer fan-out
│   │   ├── LogAggregator.swift  # Real-time log streaming (OSLog + file tail)
│   │   ├── ConfigFileManager.swift # Bundle resource loading for defaults
│   │   └── ConfigSyncService.swift # Config synchronization service
│   ├── Views/
│   │   ├── MainWindow/           # NavigationSplitView: sidebar, chat, inspector, new session sheet
│   │   │   ├── TaskCreationSheet.swift
│   │   │   └── TaskEditSheet.swift
│   │   ├── AgentLibrary/         # Agent grid + editor
│   │   ├── Debug/                # DebugLogView — unified log viewer with filters
│   │   └── Components/           # MessageBubble, ToolCallView, TreeNode, etc.
│   └── Resources/
│       ├── Assets.xcassets
│       ├── ClaudeStudio.entitlements
│       ├── DefaultAgents/           # 7 built-in agent definitions (JSON)
│       ├── DefaultSkills/           # 6 ClaudeStudio-specific skills (SKILL.md)
│       │   ├── peer-collaboration/
│       │   ├── blackboard-patterns/
│       │   ├── delegation-patterns/
│       │   ├── workspace-collaboration/
│       │   ├── agent-identity/
│       │   └── task-board-patterns/
│       ├── DefaultMCPs.json         # Pre-registered MCP server configs
│       ├── DefaultPermissionPresets.json  # 5 permission presets
│       └── SystemPromptTemplates/   # 3 reusable prompt templates
│
└── sidecar/                      # TypeScript Sidecar (Bun + Agent SDK)
    ├── package.json              # @anthropic-ai/claude-agent-sdk
    ├── tsconfig.json
    ├── src/
    │   ├── index.ts              # Entry: boot WS + HTTP servers
    │   ├── ws-server.ts          # WebSocket command router
    │   ├── http-server.ts        # Blackboard REST API
    │   ├── session-manager.ts    # Agent SDK query() lifecycle
    │   ├── types.ts              # Shared command/event types
    │   ├── logger.ts             # Structured JSON-line logger
    │   ├── api-router.ts         # REST API router (tasks, future endpoints)
    │   ├── relay-client.ts       # Relay client for remote connections
    │   ├── webhook-manager.ts    # Webhook event delivery
    │   ├── prompts/              # plan-mode.ts — plan mode system prompt
    │   ├── stores/
    │   │   ├── blackboard-store.ts   # In-memory + JSON disk persistence
    │   │   ├── session-registry.ts   # Per-session state tracking
    │   │   └── task-board-store.ts   # Task persistence + atomic claiming
    │   └── tools/
    │       ├── tool-context.ts       # Shared context (stores, broadcast, spawnSession)
    │       ├── peerbus-server.ts     # MCP server factory for PeerBus tools
    │       ├── ask-user-tool.ts      # Interactive input (form, options, toggle, rating)
    │       ├── rich-display-tools.ts # render_content, show_progress, suggest_actions
    │       ├── chat-tools.ts         # peer_chat_start/reply/listen/close/invite, group_invite_agent
    │       ├── messaging-tools.ts    # peer_send/broadcast/receive/list/delegate
    │       └── task-board-tools.ts   # task_board_list/create/claim/update
    └── test/
        ├── integration/
        │   ├── peerbus-tools.test.ts
        │   └── task-board-tools.test.ts
        ├── unit/
        │   └── task-board-store.test.ts
        └── api/
            └── ws-protocol.test.ts
```

## Prerequisites

- **macOS 14.0+** (Sonoma or later)
- **Xcode 16+** with Swift 6
- **Bun** runtime (`brew install oven-sh/bun/bun` or `curl -fsSL https://bun.sh/install | bash`)
- **Anthropic API key** set as `ANTHROPIC_API_KEY` environment variable (used by the Agent SDK)

## Setup

### 1. Clone and install sidecar dependencies

```bash
git clone <repo-url> ClaudeStudio
cd ClaudeStudio/sidecar
bun install
```

### 2. Open in Xcode

```bash
open ClaudeStudio.xcodeproj
```

Or generate via XcodeGen if needed:

```bash
xcodegen generate
```

### 3. Build and run

Build the `ClaudeStudio` target in Xcode (Cmd+R). The app automatically:
1. Launches the Bun sidecar process
2. Connects via WebSocket on `localhost:9849`
3. Logs sidecar output to `~/.claudestudio/logs/sidecar.log`

### Running the sidecar standalone (development)

```bash
cd sidecar
bun run dev          # watch mode
# or
bun run start        # single run
```

Environment variables:
- `CLAUDESTUDIO_WS_PORT` — WebSocket port (default: `9849`)
- `CLAUDESTUDIO_HTTP_PORT` — Blackboard HTTP API port (default: `9850`)

## Launch Parameters

ClaudeStudio accepts CLI arguments and a `claudestudio://` URL scheme for scripting, automation, and deeplinks.

### CLI arguments

```bash
# Freeform chat (no agent)
open ClaudeStudio.app --args --chat

# Start with a specific agent
open ClaudeStudio.app --args --agent Coder

# Agent with auto-sent prompt and custom working directory
open ClaudeStudio.app --args --agent Coder --prompt "Fix the failing tests" --workdir ~/code/my-project

# Group chat in autonomous mode
open ClaudeStudio.app --args --group "Dev Team" --autonomous --prompt "Ship the login feature"

# Combined with --instance for isolated workspaces
open -n ClaudeStudio.app --args --instance project-x --agent Coder --workdir ~/code/project-x
```

| Flag | Description |
|---|---|
| `--chat` | Open a freeform chat (no agent) |
| `--agent <name>` | Start a session with a named agent (case-insensitive) |
| `--group <name>` | Start a group chat with a named group (case-insensitive) |
| `--prompt <text>` | Initial message, auto-sent when sidecar connects |
| `--workdir <path>` | Override the session working directory |
| `--autonomous` | Start in autonomous mode |
| `--instance <name>` | Run in an isolated instance (existing flag) |

### URL scheme

```bash
open "claudestudio://chat?prompt=Hello"
open "claudestudio://agent/Coder?prompt=Fix%20the%20tests&workdir=/Users/me/project"
open "claudestudio://group/Dev%20Team?autonomous=true"
```

URL format: `claudestudio://<mode>/<name>?prompt=...&workdir=...&autonomous=true`

Where `<mode>` is `chat`, `agent`, or `group`. Query parameters are optional.

## Communication Protocol

### Swift → Sidecar (commands)

| Command | Purpose |
|---|---|
| `session.create` | Start a new Agent SDK session with an `AgentConfig` |
| `session.message` | Send a user message to an active session |
| `session.resume` | Resume a previous session by Claude session ID |
| `session.fork` | Fork a conversation at the current point |
| `session.pause` | Pause/abort a running session |
| `config.setLogLevel` | Set sidecar log level dynamically |
| `delegate.task` | User-initiated task delegation to agent |

### Sidecar → Swift (events)

| Event | Purpose |
|---|---|
| `stream.token` | Streaming text token from agent |
| `stream.toolCall` | Agent started a tool call |
| `stream.toolResult` | Tool call completed |
| `session.result` | Agent turn completed (with cost) |
| `session.error` | Error in session |
| `stream.image` | Streaming image from agent |
| `stream.fileCard` | File card display from agent |
| `stream.thinking` | Extended thinking content |
| `session.planComplete` | Plan mode plan completed |
| `peer.chat` | Inter-agent chat message |
| `peer.delegate` | Task delegation event |
| `blackboard.update` | Blackboard key changed |
| `task.created` | Task board task created |
| `task.updated` | Task board task updated |
| `conversation.inviteAgent` | Agent invited to join conversation |

## Blackboard HTTP API

The sidecar exposes a REST API on `localhost:9850` for external integration:

```bash
# Write a value
curl -X POST http://localhost:9850/blackboard/write \
  -H 'Content-Type: application/json' \
  -d '{"key": "research.results", "value": "[\"item1\", \"item2\"]", "writtenBy": "cli"}'

# Read a value
curl http://localhost:9850/blackboard/read?key=research.results

# Query by glob pattern
curl http://localhost:9850/blackboard/query?pattern=research.*

# List all keys
curl http://localhost:9850/blackboard/keys

# Health check
curl http://localhost:9850/blackboard/health
```

## Task Board REST API

The sidecar exposes task management endpoints on the same HTTP port:

```bash
# List tasks (with optional filters)
curl http://localhost:9850/api/v1/tasks?status=ready

# Create a task
curl -X POST http://localhost:9850/api/v1/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title": "Fix login bug", "priority": "high"}'

# Update a task
curl -X PATCH http://localhost:9850/api/v1/tasks/TASK_ID \
  -H 'Content-Type: application/json' \
  -d '{"status": "done", "result": "Fixed null check in auth.swift"}'

# Claim a task (atomic)
curl -X POST http://localhost:9850/api/v1/tasks/TASK_ID/claim \
  -H 'Content-Type: application/json' \
  -d '{"assignedTo": "Coder-session-1"}'
```

## Data Model

The app uses SwiftData with these core entities:

- **Agent** — reusable template (like a class): skills, MCPs, permissions, model, instance policy
- **Session** — running instance (like an object): status, mode, workspace, cost tracking
- **Conversation** — unified communication primitive for user↔agent and agent↔agent; supports `planModeEnabled` for interactive planning; **group chats** attach multiple `Session`s, send each user message to every agent, and **fan out** each assistant reply to other agents via extra `session.message` calls (see `SPEC.md` FR-4.9)
- **Participant** — member of a conversation (`.user` or `.agentSession`)
- **Skill / MCPServer / PermissionSet** — composable building blocks for agents
- **BlackboardEntry** — shared structured knowledge (key-value + metadata)
- **SharedWorkspace** — directory shared between multiple agent sessions
- **Peer** — discovered network peer (P2P, planned)
- **TaskItem** — task board item with lifecycle (backlog → ready → inProgress → done/failed), priority, labels, agent assignment

## Built-in Ecosystem

ClaudeStudio ships with 7 default agents, 6 multi-agent skills, MCP integrations, permission presets, and system prompt templates -- all designed to work together out of the box. Users can modify, duplicate, or delete any default.

### Default Agents

| Agent | Role | Model | Instance Policy | Permissions |
|---|---|---|---|---|
| **Orchestrator** | Breaks tasks into subtasks, delegates to specialists, synthesizes results | opus | `.spawn` | Full Access |
| **Coder** | Writes, edits, and refactors code in shared workspaces | sonnet | `.pool(3)` | Full Access |
| **Reviewer** | Reviews code and PRs; never writes production code | sonnet | `.singleton` | Read Only + git |
| **Researcher** | Gathers information from web, docs, codebases; writes to blackboard | sonnet | `.spawn` | Read Only + web |
| **Tester** | Writes/runs tests, uses Argus for UI testing | sonnet | `.pool(2)` | Full Access |
| **DevOps** | Git workflows, CI/CD, deployment, environment setup | haiku | `.singleton` | Git Only |
| **Writer** | Documentation, READMEs, specs, PRDs, UX copy | sonnet | `.spawn` | Read + Write Docs |

### ClaudeStudio-Specific Skills

- **`peer-collaboration`** -- PeerBus usage: blocking chat vs async, deadlock avoidance, group chat etiquette
- **`blackboard-patterns`** -- Key naming conventions, structured data patterns, subscription strategies
- **`delegation-patterns`** -- Task decomposition, wait strategies, pipeline templates (sequential, parallel, iterative)
- **`workspace-collaboration`** -- Multi-agent file conventions, locking, readiness signaling
- **`agent-identity`** -- ClaudeStudio context injection, peer discovery, self-introduction protocol
- **`task-board-patterns`** -- Task polling, subtask decomposition, atomic claiming, result reporting

### MCP Integrations (pre-registered, user-enabled per agent)

Argus (UI testing), AppXray (runtime inspection), GitHub (issues/PRs), Sentry (error monitoring), Linear/Jira (issue tracking), Slack/Discord (notifications).

### Permission Presets

Full Access, Read Only, Read + Write Docs, Git Only, Sandbox.

See [`system-plan-vision.md` Section 11](system-plan-vision.md#11-built-in-ecosystem) for full specifications.

## Current Status

**Implemented (Phase 1-12):**
- Swift project with SwiftData models for all core entities
- Bun sidecar with Agent SDK `query()` integration
- WebSocket communication (commands + streaming events)
- SidecarManager with process lifecycle and auto-reconnect
- AgentProvisioner composing configs from SwiftData models
- Main window with NavigationSplitView (sidebar, chat, inspector)
- Agent library with editor (Start button launches sessions)
- Blackboard with HTTP REST API and disk persistence
- Working directory resolution (explicit, GitHub clone, agent default, ephemeral)
- New Session sheet with agent picker, model/mode/mission/directory options (Cmd+N)
- Conversation management: rename, pin, archive, close, delete, duplicate
- Group chat: shared transcript per session, sequential replies, automatic peer fan-out
- PeerBus custom tools: peer_chat, peer_delegate, peer_send/broadcast/receive, blackboard, workspace (17 tools)
- Agent-to-agent conversations and delegation with instance policy enforcement
- Built-in ecosystem: 7 default agents, 6 skills, MCP configs, permission presets, prompt templates
- First-launch SwiftData seeding from bundled resources
- P2P LAN networking via Bonjour (agent export/import)
- Inspector file tree with git status, syntax highlighting, diff view
- Chat export (Markdown, HTML, PDF), file/image attachments
- Streaming images, file cards, and extended thinking from sidecar
- Multi-instance support (isolated data, ports, settings per instance)
- Launch parameters (CLI args + `claudestudio://` URL scheme)
- Catalog system: 30 agents, 101 skills, 100 MCPs with cascading install
- Full accessibility coverage (347+ identifiers)
- Rich display tools: ask_user (form/options/toggle/rating), render_content, show_progress, suggest_actions
- Task board: task lifecycle management, PeerBus tools, REST API, sidebar integration
- Plan mode: interactive planning with Opus, requirement gathering, visual plan presentation
- Structured logging: sidecar JSON logger + Swift OSLog + unified DebugLogView

**Planned (see `system-plan-vision.md`):**
- Crash recovery (sidecar watchdog, automatic session reconnect on restart)
- P2P v2: peer registry in sidecar, PeerBus remote routing, cross-machine relay
- Blackboard as MCP server (universal AI tool integration)

## Runtime Paths

| Path | Purpose |
|---|---|
| `~/.claudestudio/logs/` | Sidecar stdout/stderr logs |
| `~/.claudestudio/blackboard/` | Persisted blackboard JSON files |
| `~/.claudestudio/repos/` | Cloned GitHub repositories |
| `~/.claudestudio/sandboxes/` | Ephemeral session working directories |
| `~/.claudestudio/workspaces/` | Shared multi-agent workspaces |

## License

Private — not yet open-sourced.
