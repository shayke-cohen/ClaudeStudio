# ClaudeStudio — Claude Code Configuration

Project-specific rules and context for AI coding agents working on ClaudeStudio.

## Project Overview

ClaudeStudio is a native macOS app (Swift 6 / SwiftUI / SwiftData) with a TypeScript sidecar (Bun + Claude Agent SDK). The two processes communicate over a local WebSocket. See `system-plan-vision.md` for the full architecture vision.

## Architecture Rules

### Two-Process Boundary

- **Swift app** owns: UI, persistence (SwiftData), P2P networking, agent provisioning
- **TypeScript sidecar** owns: Claude Agent SDK sessions, blackboard store, future PeerBus tools
- Communication is **WebSocket JSON only** — never import Swift types in TS or vice versa
- Keep the wire protocol types in sync: `SidecarProtocol.swift` ↔ `sidecar/src/types.ts`

### Swift Conventions

- **Swift 6 strict concurrency** — all UI-touching code must be `@MainActor`
- **SwiftData** for persistence — use `@Model`, `@Query`, `ModelContext`
- **No ViewModels** — views use `@Query` and `@Environment(\.modelContext)` directly
- `AppState` is the single `@ObservableObject` for global UI state (sidecar status, selections, streaming buffers)
- Use `AsyncStream` for event flows from `SidecarManager` to `AppState`
- Target: **macOS 14.0+**, bundle ID: `com.claudestudio.app`

### TypeScript Conventions

- **Bun** runtime — use Bun APIs (`Bun.serve`, `Bun.write`) where available
- **ES modules** — all imports use `.js` extensions
- Claude Agent SDK: use `query()` from `@anthropic-ai/claude-agent-sdk`
- Session manager uses `permissionMode: "bypassPermissions"` for development
- Blackboard persists to `~/.claudestudio/blackboard/{scope}.json`
- Structured JSON logging via `logger.ts` — use `logger.info/warn/error/debug()` with categories, not `console.log()`

### Wire Protocol

Commands (Swift → Sidecar) and events (Sidecar → Swift) are defined in:
- Swift: `ClaudeStudio/Services/SidecarProtocol.swift` — `SidecarCommand`, `SidecarEvent`, `IncomingWireMessage`
- TypeScript: `sidecar/src/types.ts` — `SidecarCommand`, `SidecarEvent`

When adding a new command or event:
1. Add the type to both `SidecarProtocol.swift` and `types.ts`
2. Add encoding in `SidecarCommand.encodeToJSON()` (Swift side)
3. Add handling in `ws-server.ts` (sidecar side)
4. Add decoding in `IncomingWireMessage.toEvent()` (Swift side, for events)
5. Add handling in `AppState.handleEvent()` (Swift side, for events)

Note: recent wire additions include `stream.image`, `stream.fileCard`, `stream.thinking`, `session.planComplete`, `task.created`, `task.updated`, `task.list.result`, `conversation.inviteAgent`, `config.setLogLevel` (command).

## File System Rules

- **Never modify** `system-plan-vision.md` without explicit request — it's the architecture source of truth
- **Swift sources** go under `ClaudeStudio/` following the existing directory structure
- **Sidecar sources** go under `sidecar/src/`
- **Tests** go under `sidecar/test/`
- Runtime data goes under `~/.claudestudio/` (logs, blackboard, repos, sandboxes, workspaces)

## Build System

- Xcode project is managed with **XcodeGen** (`project.yml`)
- After adding new Swift files, you may need to regenerate: `xcodegen generate`
- Sidecar dependencies via `bun install` in the `sidecar/` directory
- The only external dependency is `@anthropic-ai/claude-agent-sdk`
- SPM local package: **AppXray** at `Dependencies/appxray/packages/sdk-ios` (DEBUG only)

## Key Ports

| Port | Service | Configurable Via |
|---|---|---|
| 9849 | WebSocket (Swift ↔ Sidecar) | `CLAUDESTUDIO_WS_PORT` |
| 9850 | Blackboard HTTP API | `CLAUDESTUDIO_HTTP_PORT` |

The Task Board REST API is served on the same HTTP port (9850) under `/api/v1/tasks`.

## Data Model (SwiftData)

Core entities (all in `ClaudeStudio/Models/`):

- `Agent` — template with skills, MCPs, permissions, instance policy, optional GitHub repo
- `Session` — running instance with status, mode, workspace type, cost tracking
- `Conversation` — unified model for user↔agent and agent↔agent communication
- `Participant` — `.user` or `.agentSession(sessionId)`
- `ConversationMessage` — message with type enum (text, toolCall, toolResult, delegation, blackboard)
- `Skill`, `MCPServer`, `PermissionSet` — composable building blocks
- `SharedWorkspace`, `BlackboardEntry`, `Peer` — collaboration primitives
- `TaskItem` — task board item with lifecycle (backlog/ready/inProgress/done/failed/blocked), priority, labels, agent assignment

## What's Implemented vs Planned

**Implemented (Phases 1–6):**
- SwiftData models for all entities
- SidecarManager (process launch, WebSocket, reconnect)
- SidecarProtocol (commands: create/message/resume/fork/pause; events: token/toolCall/toolResult/result/error/streamImage/streamFileCard/streamThinking)
- AgentProvisioner (resolves skills, MCPs, permissions, working directory → AgentConfig)
- SessionManager in sidecar (Agent SDK `query()`, streaming, resume, fork, pause)
- Blackboard store (in-memory + disk + HTTP REST API)
- Main UI (NavigationSplitView with sidebar, chat, inspector)
- Agent library, editor, and catalog browser views
- PeerBus SDK tools (peer_chat_*, peer_send_*, blackboard_*, workspace_*) with stores
- Agent-to-agent messaging, blocking chats, delegation routing
- Agent Comms view (unified timeline with filter tabs)
- Built-in ecosystem (default agents, skills, MCPs, permission presets, system prompt templates, first-launch seeding)
- Session persistence (SwiftData + `claudeSessionId` for SDK resume)
- Conversation forking (from any pivot message, with lineage tracking)
- GitHub workspace clone (`GitHubIntegration.swift`, `WorkspaceResolver.swift`)
- Chat export/share (Markdown, HTML, PDF via `ChatTranscriptExport`)
- File and image attachments (drag-drop, thumbnails, `MessageAttachment` model)
- Streaming images, file cards, and extended thinking from sidecar
- Inspector file tree with git status integration
- Resizable chat/inspector split with persistent divider
- Conversation archive/unarchive
- Multi-instance support (`InstanceConfig`, `--instance` flag)
- Launch parameters (`LaunchIntent`, `--chat`/`--agent`/`--group`/`--prompt`/`--workdir`/`--autonomous`) and `claudestudio://` URL scheme
- Group peer fan-out (`GroupPeerFanOutContext`, budget limiter, deduplication)
- P2P LAN networking (Bonjour discovery, `PeerCatalogServer`, `PeerAgentImporter`, `PeerNetworkView`)
- Full accessibility coverage (347+ identifiers)
- Rich display tools (ask_user with form/options/toggle/rating input types, render_content, show_progress, suggest_actions) as in-process MCP
- Auto-expanding chat input with Shift+Enter newlines
- Task board system (TaskItem model, TaskBoardStore, PeerBus tools, REST API, sidebar integration)
- Plan mode (custom system prompt injection, Opus override, interactive planning workflow)
- Structured logging infrastructure (sidecar JSON logger, Swift OSLog with categories, UnifiedLogEntry, LogAggregator, DebugLogView)
- Sidebar bottom bar refactoring (SidebarBottomBarItem enum, adaptive layout)
- group_invite_agent chat tool for dynamic agent invitation to conversations
- Config file management and sync services

**Not yet implemented (specified in vision doc):**

- Crash recovery (sidecar watchdog, automatic session reconnect on restart)
- Instance policy enforcement (.singleton, .pool with load balancing)
- GitHub CLI (`gh`) integration, branch-from-issue workflow
- P2P v2: peer registry in sidecar, PeerBus remote routing, cross-machine relay
- Blackboard as MCP server (universal AI tool integration)

## Accessibility Identifiers (AppXray / UI Testing)

Every interactive or semantically meaningful SwiftUI element must have an `.accessibilityIdentifier()` so AppXray can target it via `@testId("...")` selectors.

### Naming Convention

Dot-separated `viewName.elementName` in camelCase:
- Static: `"chat.sendButton"`, `"sidebar.conversationList"`
- Dynamic rows: `"sidebar.conversationRow.\(id.uuidString)"`
- Nested: `"agentEditor.skills.addButton.\(skill.id.uuidString)"`
- Settings: `"settings.general.appearancePicker"`, `"settings.connection.wsPortField"`

### Rules

- **Buttons with text**: `.accessibilityIdentifier()` only
- **Icon-only buttons**: `.accessibilityIdentifier()` + `.accessibilityLabel("Human-readable action")`
- **TextFields / TextEditors / Pickers / Toggles / Steppers**: `.accessibilityIdentifier()`
- **Lists / ScrollViews**: `.accessibilityIdentifier()` on the container
- **Dynamic ForEach rows**: suffix with `.\(item.id.uuidString)`
- **Decorative elements**: `.accessibilityElement(children: .ignore)`
- **Never reuse** an identifier across different views

### Prefix Map

| View | Prefix |
|---|---|
| MainWindowView | `mainWindow.*` |
| SidebarView | `sidebar.*` |
| ChatView | `chat.*` |
| InspectorView | `inspector.*` |
| NewSessionSheet | `newSession.*` |
| AgentLibraryView | `agentLibrary.*` |
| AgentEditorView | `agentEditor.*` |
| AgentCommsView | `agentComms.*` |
| PeerNetworkView | `peerNetwork.*` |
| SettingsView | `settings.{general,connection,developer}.*` |
| AgentCardView | `agentCard.*` |
| MessageBubble | `messageBubble.*` |
| ToolCallView | `toolCall.*` |
| CodeBlockView | `codeBlock.*` |
| StatusBadge | `statusBadge.*` |
| StreamingIndicator | `streamingIndicator` |
| InfoRow | `infoRow.*` |
| DelegateSheet | `delegate.*` |
| ImagePreviewOverlay | `imagePreview.*` |
| ConversationTreeNode | `conversationTree.*` |
| MarkdownContent | `markdownContent` |
| HighlightedCodeView | `highlightedCode.*` |
| PasteableTextField | `pasteableTextField.*` |
| CatalogBrowserView | `catalog.*` |
| CatalogDetailView | `catalogDetail.*` |
| MCPEditorView | `mcpEditor.*` |
| MCPLibraryView | `mcpLibrary.*` |
| MCPCatalogSheet | `mcpCatalogSheet.*` |
| SkillEditorView | `skillEditor.*` |
| SkillLibraryView | `skillLibrary.*` |
| AttachmentThumbnail | `attachmentThumbnail.*` |
| FileExplorerView | `inspector.fileTree.*` |
| FileContentView | `inspector.fileContent.*` |
| FileTreeView | `inspector.fileTree.*` |
| WorkingDirectoryPicker | `directoryPicker.*` |
| AttachRepoSheet | `attachRepo.*` |
| DebugLogView | `debugLog.*` |
| TaskCreationSheet | `taskCreation.*` |
| TaskEditSheet | `taskEdit.*` |

When adding new views, pick a unique camelCase prefix and annotate every interactive element.

## Testing

See `TESTING.md` for the complete testing guide, including:
- XCTest: group chat coverage in `ClaudeStudioTests/GroupPromptBuilderTests.swift` (transcript, peer prompts, fan-out context)
- Three testing layers (XCTest, AppXray, Argus)
- Full screen-by-screen control inventory with all `accessibilityIdentifier` and `accessibilityLabel` values
- AppXray selector syntax (`@testId`, `@label`, `@text`, `@type`)
- Argus macOS E2E examples and YAML regression test format
- Dynamic identifier patterns and known gaps

## Common Tasks

### Adding a new SwiftData model
1. Create `ClaudeStudio/Models/NewModel.swift` with `@Model` class
2. Add to the model container in `ClaudeStudioApp.swift` `.modelContainer(for: [...])`
3. Regenerate Xcode project if needed: `xcodegen generate`

### Adding a new sidecar command
1. Add type to `SidecarCommand` union in `sidecar/src/types.ts`
2. Add Swift enum case in `SidecarProtocol.swift`
3. Add wire struct and encoding in `SidecarCommand.encodeToJSON()`
4. Add handler in `sidecar/src/ws-server.ts`

### Adding a new sidecar event
1. Add type to `SidecarEvent` union in `sidecar/src/types.ts`
2. Add Swift enum case in `SidecarEvent` in `SidecarProtocol.swift`
3. Add decoding case in `IncomingWireMessage.toEvent()`
4. Add handler in `AppState.handleEvent()`

### Adding a new launch parameter

1. Add the flag to `LaunchIntent.fromCommandLine()` in `ClaudeStudio/App/LaunchIntent.swift`
2. Add the URL query parameter to `LaunchIntent.fromURL()` in the same file
3. Add any new fields to the `LaunchIntent` struct
4. Handle the new field in `AppState.executeLaunchIntent()` in `ClaudeStudio/App/AppState.swift`

### Launch parameter flow

- **Parsing**: `LaunchIntent.fromCommandLine()` (eager, at `init()` time) or `LaunchIntent.fromURL()` (on `onOpenURL`)
- **Execution**: `AppState.executeLaunchIntent(_:modelContext:)` — SwiftData lookup + session creation
- **Prompt queue**: `AppState.pendingAutoPrompt` — drained on sidecar `.connected` event via `drainPendingAutoPrompt()`
- **Errors**: `AppState.launchError` — shown as alert in `MainWindowView`
- **URL scheme**: `claudestudio://` registered in `ClaudeStudio/Resources/Info.plist`

### Adding a new task board tool

1. Add the tool schema in `sidecar/src/tools/task-board-tools.ts`
2. Add the task type/fields in `sidecar/src/stores/task-board-store.ts`
3. Add wire types in `sidecar/src/types.ts`
4. Add REST endpoint in `sidecar/src/api-router.ts` if needed
5. Add Swift wire structs in `SidecarProtocol.swift`
6. Add event handling in `AppState.handleEvent()`
