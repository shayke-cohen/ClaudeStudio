# AGENTS.md — ClaudPeer Codebase Guide

This file helps AI coding agents navigate the ClaudPeer codebase efficiently.

## Quick Orientation

ClaudPeer = **Swift macOS app** + **TypeScript Bun sidecar**, talking over **WebSocket JSON**.

```
User ↔ SwiftUI ↔ AppState ↔ SidecarManager ↔ [WebSocket] ↔ WsServer ↔ SessionManager ↔ Claude Agent SDK
```

## Codebase Map

### Swift App (`ClaudPeer/`)

#### Entry Points
- `App/ClaudPeerApp.swift` — `@main`, window setup, model container registration, sidecar connect on appear
- `App/AppState.swift` — `@MainActor ObservableObject`: sidecar status, active sessions, streaming text buffers, event handling, UI sheet toggles (`showNewSessionSheet`, `showAgentLibrary`, `showPeerNetwork`)

#### Models (`Models/`)
All are SwiftData `@Model` classes. Relationships use UUID references (not SwiftData `@Relationship`) for flexibility.

| File | Entity | Key Fields |
|---|---|---|
| `Agent.swift` | Agent template | name, systemPrompt, skillIds, mcpServerIds, permissionSetId, model, instancePolicy, githubRepo |
| `Session.swift` | Running instance | agent, status, mode, workingDirectory, workspaceType, claudeSessionId, cost |
| `Conversation.swift` | Chat primitive | participants, messages, parentConversation, status, isPinned |
| `ConversationMessage.swift` | Single message | sender, text, messageType (text/toolCall/toolResult/delegation/blackboard) |
| `Participant.swift` | Conversation member | type (.user/.agentSession), displayName, role (.active/.observer) |
| `Skill.swift` | Skill definition | name, content (markdown), category, triggers, source |
| `MCPServer.swift` | MCP config | name, transport (.stdio/.http), tools, resources |
| `PermissionSet.swift` | Permission preset | allowRules, denyRules, permissionMode |
| `SharedWorkspace.swift` | Shared directory | name, path, participants |
| `BlackboardEntry.swift` | Key-value entry | key, value (JSON), writtenBy, workspaceId |
| `Peer.swift` | Network peer | displayName, hostName, sharedAgents, status |

#### Services (`Services/`)

| File | Role | Key Methods |
|---|---|---|
| `SidecarManager.swift` | Process + WebSocket lifecycle | `start()`, `stop()`, `send()`, `events` (AsyncStream) |
| `SidecarProtocol.swift` | Wire types | `SidecarCommand` (enum), `SidecarEvent` (enum), `AgentConfig` (struct), `IncomingWireMessage` |
| `AgentProvisioner.swift` | Config builder | `provision(agent:mission:)` → (AgentConfig, Session) |

**SidecarManager** finds Bun at `/opt/homebrew/bin/bun`, `/usr/local/bin/bun`, or `~/.bun/bin/bun`. Finds sidecar at: bundle resources, cwd, `~/ClaudPeer/sidecar/`, or `UserDefaults["claudpeer.projectPath"]`.

**AgentProvisioner** resolves working directory by priority: explicit override → GitHub clone path → agent default → ephemeral sandbox. Appends PeerBus tool names to allowedTools (forward-looking; tools not yet implemented in sidecar).

#### Views (`Views/`)

| Directory | Files | Purpose |
|---|---|---|
| `MainWindow/` | MainWindowView, SidebarView, ChatView, InspectorView, NewSessionSheet | Three-panel layout + session creation |
| `AgentLibrary/` | AgentLibraryView, AgentEditorView | Agent CRUD |
| `Components/` | MessageBubble, ToolCallView, ConversationTreeNode, StatusBadge, StreamingIndicator, AgentCardView | Reusable UI |

**MainWindowView** is a `NavigationSplitView` with sidebar (conversation list + agents), detail (ChatView), and trailing column (InspectorView). Toolbar has New Session (Cmd+N, opens `NewSessionSheet`), Quick Chat (Cmd+Shift+N), Agent Library, Peer Network, and sidecar status.

**NewSessionSheet** presents an agent picker grid (all agents + freeform option), model override dropdown, session mode picker (interactive/autonomous/worker), mission text field, and working directory picker with folder browser.

**SidebarView** organizes conversations into Pinned, Active, and Recent sections. Each row shows agent icon, auto-generated topic, relative timestamp, and last message preview. Context menu offers: Rename, Pin/Unpin, Close, Duplicate, Delete. Swipe actions: delete (trailing), pin (leading). Empty state shows when no conversations exist.

**ChatView** handles message sending with auto-naming (first message sets topic). Header shows: editable topic (pencil icon), model pill, live cost, Fork/Pause/Resume/Close buttons, and overflow menu (Clear Messages, Duplicate). On first message with a linked session+agent, it calls `AgentProvisioner.provision()` → `session.create` → `session.message`. Streaming text is polled from `AppState.streamingText[sessionId]`.

**InspectorView** shows conversation metadata with actionable controls: editable topic, Close button, session Pause/Resume/Stop buttons (state-dependent), live token/cost counters from AppState, and "Open in Editor" link to Agent Library.

**AgentCardView** has a working Start button that creates a session and dismisses the library.

#### Accessibility Identifiers

All views have `.accessibilityIdentifier()` modifiers for AppXray UI testing (`@testId()` selector). The naming convention is `viewName.elementName` in dot-separated camelCase. Dynamic rows append `.\(item.id.uuidString)`. Icon-only buttons also have `.accessibilityLabel()`. See `CLAUDE.md` "Accessibility Identifiers" section for the full prefix map and rules. When adding new views, follow the same convention.

### TypeScript Sidecar (`sidecar/`)

#### Entry Point
- `src/index.ts` — creates BlackboardStore, WsServer (port 9849), HttpServer (port 9850), signal handlers

#### Core Modules

| File | Role | Key Exports |
|---|---|---|
| `src/ws-server.ts` | WebSocket command router | `WsServer` — handles `session.*` commands, delegates to SessionManager, broadcasts events |
| `src/session-manager.ts` | Agent SDK integration | `SessionManager` — `createSession()`, `sendMessage()`, `resumeSession()`, `forkSession()`, `pauseSession()` |
| `src/http-server.ts` | Blackboard REST API | `HttpServer` — CRUD on `/blackboard/*`, CORS for localhost |
| `src/types.ts` | Shared types | `SidecarCommand`, `SidecarEvent`, `AgentConfig`, `SessionState`, `BlackboardEntry` |

#### Stores

| File | Role |
|---|---|
| `stores/blackboard-store.ts` | In-memory Map + JSON disk at `~/.claudpeer/blackboard/{scope}.json` |
| `stores/session-registry.ts` | Per-session state (config, status, claudeSessionId, cost) |

#### SDK Integration (`session-manager.ts`)

`sendMessage()` calls `query({ prompt, options })` and iterates the async stream. Message types handled:
- `assistant` → extract text blocks → emit `stream.token`
- `tool_use` → emit `stream.toolCall`
- `tool_result` → emit `stream.toolResult`
- `result` → capture cost + SDK session ID
- `error` → emit `session.error`

Query options include: model (default `claude-sonnet-4-6`), maxTurns (30), systemPrompt (preset `claude_code` + append), MCP servers, allowed tools, resume/sessionId.

## Data Flow: User Sends a Message

```
1. ChatView: user types message, saves ConversationMessage to SwiftData
2. ChatView: calls appState.sendToSidecar(.sessionMessage(sessionId, text))
3. AppState → SidecarManager.send() → WebSocket JSON
4. WsServer receives → SessionManager.sendMessage()
5. SessionManager calls query({ prompt: text, options })
6. SDK streams messages → SessionManager.handleSDKMessage()
7. Each message → emit SidecarEvent → WsServer.broadcast() → WebSocket JSON
8. SidecarManager.receiveMessages() → decode → eventContinuation.yield()
9. AppState.handleEvent() → updates streamingText[sessionId]
10. ChatView observes AppState, renders streaming text
```

## Data Flow: First Message (Session Creation)

```
1. ChatView detects: no active sidecar session for this conversation
2. AgentProvisioner.provision(agent, mission) → (AgentConfig, Session)
3. Session saved to SwiftData
4. appState.sendToSidecar(.sessionCreate(conversationId, agentConfig))
5. WsServer → SessionManager.createSession() → registers in SessionRegistry
6. Then: appState.sendToSidecar(.sessionMessage(sessionId, text))
7. Normal message flow continues from step 4 above
```

## Known Gaps (Vision vs Implementation)

These are specified in `system-plan-vision.md` but not yet in code:

| Area | What's Missing |
|---|---|
| PeerBus tools | `tools/peer-*.ts`, `tools/blackboard.ts`, `tools/workspace.ts` — custom SDK tools |
| Hook engine | `hooks/ui-hooks.ts`, `hooks/peer-hooks.ts` — PreToolUse/PostToolUse callbacks |
| Agent-to-agent | Blocking chat, delegation routing, instance policy enforcement |
| WorkspaceResolver | `Services/WorkspaceResolver.swift` — full resolution with GitHub clone |
| GitHubIntegration | `Services/GitHubIntegration.swift` — repo clone, branch management |
| P2P | `Services/P2PNetworkManager.swift` — Bonjour, WebSocket relay |
| Views | AgentCommsView, PeerNetworkView, SkillPoolView, MCPPoolView |
| Sidecar provisioner | `sidecar/src/agent-provisioner.ts` — TS-side config builder |

## Testing

See `TESTING.md` for the full testing guide — screen-by-screen control reference, AppXray selectors, Argus E2E flows, and YAML regression tests.

### Quick Reference

**Swift unit tests** (9 test files in `ClaudPeerTests/`):
```bash
xcodebuild test -project ClaudPeer.xcodeproj -scheme ClaudPeer -destination 'platform=macOS'
```

**Sidecar tests** (require a running sidecar):
```bash
cd sidecar
bun run start &
bun test
```

**AppXray** (inside-out, DEBUG builds): connect via `session({ action: "discover" })` then `session({ action: "connect", appId: "com.claudpeer.app" })`. Target elements with `@testId("chat.sendButton")`.

**Argus** (outside-in E2E): `inspect({ platform: "macos", appName: "ClaudPeer" })` to start, then `act`/`assert`/`wait` for automation.

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | — | Required by Claude Agent SDK |
| `CLAUDPEER_WS_PORT` | 9849 | WebSocket port |
| `CLAUDPEER_HTTP_PORT` | 9850 | Blackboard HTTP API port |
