# ClaudPeer — Claude Code Configuration

Project-specific rules and context for AI coding agents working on ClaudPeer.

## Project Overview

ClaudPeer is a native macOS app (Swift 6 / SwiftUI / SwiftData) with a TypeScript sidecar (Bun + Claude Agent SDK). The two processes communicate over a local WebSocket. See `system-plan-vision.md` for the full architecture vision.

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
- Target: **macOS 14.0+**, bundle ID: `com.claudpeer.app`

### TypeScript Conventions

- **Bun** runtime — use Bun APIs (`Bun.serve`, `Bun.write`) where available
- **ES modules** — all imports use `.js` extensions
- Claude Agent SDK: use `query()` from `@anthropic-ai/claude-agent-sdk`
- Session manager uses `permissionMode: "bypassPermissions"` for development
- Blackboard persists to `~/.claudpeer/blackboard/{scope}.json`

### Wire Protocol

Commands (Swift → Sidecar) and events (Sidecar → Swift) are defined in:
- Swift: `ClaudPeer/Services/SidecarProtocol.swift` — `SidecarCommand`, `SidecarEvent`, `IncomingWireMessage`
- TypeScript: `sidecar/src/types.ts` — `SidecarCommand`, `SidecarEvent`

When adding a new command or event:
1. Add the type to both `SidecarProtocol.swift` and `types.ts`
2. Add encoding in `SidecarCommand.encodeToJSON()` (Swift side)
3. Add handling in `ws-server.ts` (sidecar side)
4. Add decoding in `IncomingWireMessage.toEvent()` (Swift side, for events)
5. Add handling in `AppState.handleEvent()` (Swift side, for events)

## File System Rules

- **Never modify** `system-plan-vision.md` without explicit request — it's the architecture source of truth
- **Swift sources** go under `ClaudPeer/` following the existing directory structure
- **Sidecar sources** go under `sidecar/src/`
- **Tests** go under `sidecar/test/`
- Runtime data goes under `~/.claudpeer/` (logs, blackboard, repos, sandboxes, workspaces)

## Build System

- Xcode project is managed with **XcodeGen** (`project.yml`)
- After adding new Swift files, you may need to regenerate: `xcodegen generate`
- Sidecar dependencies via `bun install` in the `sidecar/` directory
- The only external dependency is `@anthropic-ai/claude-agent-sdk`
- SPM local package: **AppXray** at `Dependencies/appxray/packages/sdk-ios` (DEBUG only)

## Key Ports

| Port | Service | Configurable Via |
|---|---|---|
| 9849 | WebSocket (Swift ↔ Sidecar) | `CLAUDPEER_WS_PORT` |
| 9850 | Blackboard HTTP API | `CLAUDPEER_HTTP_PORT` |

## Data Model (SwiftData)

Core entities (all in `ClaudPeer/Models/`):

- `Agent` — template with skills, MCPs, permissions, instance policy, optional GitHub repo
- `Session` — running instance with status, mode, workspace type, cost tracking
- `Conversation` — unified model for user↔agent and agent↔agent communication
- `Participant` — `.user` or `.agentSession(sessionId)`
- `ConversationMessage` — message with type enum (text, toolCall, toolResult, delegation, blackboard)
- `Skill`, `MCPServer`, `PermissionSet` — composable building blocks
- `SharedWorkspace`, `BlackboardEntry`, `Peer` — collaboration primitives

## What's Implemented vs Planned

**Implemented:**
- SwiftData models for all entities
- SidecarManager (process launch, WebSocket, reconnect)
- SidecarProtocol (commands: create/message/resume/fork/pause; events: token/toolCall/toolResult/result/error)
- AgentProvisioner (resolves skills, MCPs, permissions, working directory → AgentConfig)
- SessionManager in sidecar (Agent SDK `query()`, streaming, resume, fork, pause)
- Blackboard store (in-memory + disk + HTTP REST API)
- Main UI (NavigationSplitView with sidebar, chat, inspector)
- Agent library and editor views

**Not yet implemented (specified in vision doc):**
- PeerBus custom SDK tools (peer_chat_*, peer_send_*, blackboard_*, workspace_*)
- Hook engine (PreToolUse/PostToolUse event hooks)
- Agent-to-agent conversations and delegation routing
- Instance policy enforcement (.singleton, .pool)
- P2P networking (Bonjour discovery, agent sharing, cross-machine relay)
- WorkspaceResolver.swift, GitHubIntegration.swift, P2PNetworkManager.swift
- Agent Comms view, Peer Network panel
- Skill/MCP pool management views

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

When adding new views, pick a unique camelCase prefix and annotate every interactive element.

## Testing

See `TESTING.md` for the complete testing guide, including:
- Three testing layers (XCTest, AppXray, Argus)
- Full screen-by-screen control inventory with all `accessibilityIdentifier` and `accessibilityLabel` values
- AppXray selector syntax (`@testId`, `@label`, `@text`, `@type`)
- Argus macOS E2E examples and YAML regression test format
- Dynamic identifier patterns and known gaps

## Common Tasks

### Adding a new SwiftData model
1. Create `ClaudPeer/Models/NewModel.swift` with `@Model` class
2. Add to the model container in `ClaudPeerApp.swift` `.modelContainer(for: [...])`
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
