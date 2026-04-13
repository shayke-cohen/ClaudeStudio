# Phase 4a — iOS Data Bridge (Sidecar + Mac Push) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the sidecar and Mac app to push conversation/project snapshots so iOS clients can read them via REST. This is the prerequisite data layer for Phase 4b (iOS views).

**Architecture:** Mac pushes SwiftData snapshots via new WS commands (`conversation.sync`, `project.sync`, `conversation.messageAppend`) into sidecar in-memory stores. The sidecar exposes these via new REST endpoints. iOS reads exclusively from this REST layer — it never touches SwiftData.

**Tech Stack:** TypeScript/Bun (new sidecar stores), existing `ws-server.ts`/`api-router.ts`/`types.ts`, Swift (SidecarManager + AppState edits), XcodeGen

---

### Task 1: Sidecar `ConversationStore`

**Files:**
- Create: `sidecar/src/stores/conversation-store.ts`
- Test: `sidecar/test/unit/conversation-store.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// sidecar/test/unit/conversation-store.test.ts
import { describe, test, expect, beforeEach } from "bun:test";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import type { ConversationSummaryWire, MessageWire } from "../../src/stores/conversation-store.js";

const makeConv = (id: string): ConversationSummaryWire => ({
  id, topic: "Test", lastMessageAt: "2026-04-13T10:00:00Z",
  lastMessagePreview: "Hello", unread: false, participants: [],
  projectId: null, projectName: null, workingDirectory: null,
});
const makeMsg = (id: string, text: string): MessageWire => ({
  id, text, type: "text", senderParticipantId: null,
  timestamp: "2026-04-13T10:00:00Z", isStreaming: false,
});

describe("ConversationStore", () => {
  let store: ConversationStore;
  beforeEach(() => { store = new ConversationStore(); });

  test("sync populates listConversations", () => {
    store.sync([makeConv("a"), makeConv("b")]);
    expect(store.listConversations()).toHaveLength(2);
  });

  test("appendMessage adds to getMessages", () => {
    store.sync([makeConv("c1")]);
    store.appendMessage("c1", makeMsg("m1", "hi"));
    expect(store.getMessages("c1")).toHaveLength(1);
    expect(store.getMessages("c1")[0].text).toBe("hi");
  });

  test("getMessages respects limit", () => {
    store.sync([makeConv("c2")]);
    for (let i = 0; i < 10; i++) store.appendMessage("c2", makeMsg(`m${i}`, `msg${i}`));
    expect(store.getMessages("c2", 3)).toHaveLength(3);
  });

  test("getMessages returns chronological order", () => {
    store.sync([makeConv("c3")]);
    store.appendMessage("c3", { ...makeMsg("m1", "first"), timestamp: "2026-04-13T10:00:00Z" });
    store.appendMessage("c3", { ...makeMsg("m2", "second"), timestamp: "2026-04-13T10:01:00Z" });
    const msgs = store.getMessages("c3");
    expect(msgs[0].text).toBe("first");
    expect(msgs[1].text).toBe("second");
  });

  test("sync replaces all conversations", () => {
    store.sync([makeConv("old")]);
    store.sync([makeConv("new1"), makeConv("new2")]);
    const ids = store.listConversations().map(c => c.id);
    expect(ids).not.toContain("old");
    expect(ids).toContain("new1");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/unit/conversation-store.test.ts
```
Expected: `Cannot find module '../../src/stores/conversation-store.js'`

- [ ] **Step 3: Create `ConversationStore`**

```typescript
// sidecar/src/stores/conversation-store.ts
export interface ConversationSummaryWire {
  id: string;
  topic: string;
  lastMessageAt: string;
  lastMessagePreview: string;
  unread: boolean;
  participants: ParticipantWire[];
  projectId: string | null;
  projectName: string | null;
  workingDirectory: string | null;
}

export interface MessageWire {
  id: string;
  text: string;
  type: string;
  senderParticipantId: string | null;
  timestamp: string;
  isStreaming: boolean;
  toolName?: string;
  toolOutput?: string;
  thinkingText?: string;
}

export interface ParticipantWire {
  id: string;
  displayName: string;
  isAgent: boolean;
  isLocal: boolean;
}

export class ConversationStore {
  private conversations = new Map<string, ConversationSummaryWire>();
  private messages = new Map<string, MessageWire[]>();

  sync(conversations: ConversationSummaryWire[]): void {
    this.conversations.clear();
    for (const c of conversations) {
      this.conversations.set(c.id, c);
    }
  }

  appendMessage(conversationId: string, message: MessageWire): void {
    const msgs = this.messages.get(conversationId) ?? [];
    // Replace streaming placeholder or append
    const idx = msgs.findIndex(m => m.id === message.id);
    if (idx >= 0) {
      msgs[idx] = message;
    } else {
      msgs.push(message);
    }
    this.messages.set(conversationId, msgs);
    // Update preview on conversation
    const conv = this.conversations.get(conversationId);
    if (conv && !message.isStreaming) {
      this.conversations.set(conversationId, {
        ...conv,
        lastMessageAt: message.timestamp,
        lastMessagePreview: message.text.slice(0, 100),
      });
    }
  }

  listConversations(): ConversationSummaryWire[] {
    return Array.from(this.conversations.values())
      .sort((a, b) => b.lastMessageAt.localeCompare(a.lastMessageAt));
  }

  getMessages(conversationId: string, limit?: number, before?: string): MessageWire[] {
    let msgs = this.messages.get(conversationId) ?? [];
    msgs = [...msgs].sort((a, b) => a.timestamp.localeCompare(b.timestamp));
    if (before) {
      msgs = msgs.filter(m => m.timestamp < before);
    }
    if (limit !== undefined) {
      msgs = msgs.slice(-limit);
    }
    return msgs;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/unit/conversation-store.test.ts
```
Expected: all 5 tests PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey && git add sidecar/src/stores/conversation-store.ts sidecar/test/unit/conversation-store.test.ts
git commit -m "feat(sidecar): add ConversationStore for iOS data bridge"
```

---

### Task 2: Sidecar `ProjectStore`

**Files:**
- Create: `sidecar/src/stores/project-store.ts`
- Test: `sidecar/test/unit/project-store.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// sidecar/test/unit/project-store.test.ts
import { describe, test, expect, beforeEach } from "bun:test";
import { ProjectStore } from "../../src/stores/project-store.js";
import type { ProjectSummaryWire } from "../../src/stores/project-store.js";

const makeProject = (id: string, name: string): ProjectSummaryWire => ({
  id, name, rootPath: `/Users/test/${name}`,
  icon: "folder", color: "blue", isPinned: false, pinnedAgentIds: [],
});

describe("ProjectStore", () => {
  let store: ProjectStore;
  beforeEach(() => { store = new ProjectStore(); });

  test("sync populates list()", () => {
    store.sync([makeProject("p1", "Alpha"), makeProject("p2", "Beta")]);
    expect(store.list()).toHaveLength(2);
  });

  test("sync replaces previous projects", () => {
    store.sync([makeProject("old", "Old")]);
    store.sync([makeProject("new", "New")]);
    expect(store.list().map(p => p.id)).toEqual(["new"]);
  });

  test("get returns project by id", () => {
    store.sync([makeProject("p1", "Alpha")]);
    expect(store.get("p1")?.name).toBe("Alpha");
    expect(store.get("missing")).toBeUndefined();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/unit/project-store.test.ts
```
Expected: `Cannot find module '../../src/stores/project-store.js'`

- [ ] **Step 3: Create `ProjectStore`**

```typescript
// sidecar/src/stores/project-store.ts
export interface ProjectSummaryWire {
  id: string;
  name: string;
  rootPath: string;
  icon: string;
  color: string;
  isPinned: boolean;
  pinnedAgentIds: string[];
}

export class ProjectStore {
  private projects = new Map<string, ProjectSummaryWire>();

  sync(projects: ProjectSummaryWire[]): void {
    this.projects.clear();
    for (const p of projects) {
      this.projects.set(p.id, p);
    }
  }

  list(): ProjectSummaryWire[] {
    return Array.from(this.projects.values())
      .sort((a, b) => (b.isPinned ? 1 : 0) - (a.isPinned ? 1 : 0) || a.name.localeCompare(b.name));
  }

  get(id: string): ProjectSummaryWire | undefined {
    return this.projects.get(id);
  }
}
```

- [ ] **Step 4: Run test**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/unit/project-store.test.ts
```
Expected: all 3 tests PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey && git add sidecar/src/stores/project-store.ts sidecar/test/unit/project-store.test.ts
git commit -m "feat(sidecar): add ProjectStore for iOS data bridge"
```

---

### Task 3: New WS Command Types in `sidecar/src/types.ts`

**Files:**
- Modify: `sidecar/src/types.ts`

- [ ] **Step 1: Add new command types to the `SidecarCommand` union**

Find the `SidecarCommand` type in `sidecar/src/types.ts` and add these cases:

```typescript
// Add to SidecarCommand union:
| { type: "conversation.sync"; conversations: import("./stores/conversation-store.js").ConversationSummaryWire[] }
| { type: "conversation.messageAppend"; conversationId: string; message: import("./stores/conversation-store.js").MessageWire }
| { type: "project.sync"; projects: import("./stores/project-store.js").ProjectSummaryWire[] }
| { type: "ios.registerPush"; apnsToken: string; appId: string }
```

- [ ] **Step 2: Add new event type**

```typescript
// Add to SidecarEvent union:
| { type: "ios.pushRegistered"; apnsToken: string }
```

- [ ] **Step 3: Verify TypeScript compiles**

```bash
cd /Users/shayco/Odyssey/sidecar && bun build src/index.ts --outdir /tmp/odyssey-build-check 2>&1 | head -20
```
Expected: no errors (or only existing warnings, no new type errors)

- [ ] **Step 4: Commit**

```bash
cd /Users/shayco/Odyssey && git add sidecar/src/types.ts
git commit -m "feat(sidecar): add conversation/project/push wire types for iOS"
```

---

### Task 4: Wire Commands into `ws-server.ts` + Add Stores to `ToolContext`

**Files:**
- Modify: `sidecar/src/ws-server.ts`
- Modify: `sidecar/src/index.ts`
- Modify: `sidecar/src/tools/tool-context.ts` (add stores to context)

- [ ] **Step 1: Add stores to `ToolContext`**

In `sidecar/src/tools/tool-context.ts`, find the `ToolContext` interface and add:

```typescript
import type { ConversationStore } from "../stores/conversation-store.js";
import type { ProjectStore } from "../stores/project-store.js";

// Add to ToolContext interface:
conversationStore: ConversationStore;
projectStore: ProjectStore;
```

- [ ] **Step 2: Instantiate stores in `index.ts`**

In `sidecar/src/index.ts`, add imports and instantiation:

```typescript
import { ConversationStore } from "./stores/conversation-store.js";
import { ProjectStore } from "./stores/project-store.js";

// After existing store instantiations:
const conversationStore = new ConversationStore();
const projectStore = new ProjectStore();

// Add to toolContext object:
conversationStore,
projectStore,
```

- [ ] **Step 3: Add command handlers in `ws-server.ts`**

In the `handleCommand` switch in `sidecar/src/ws-server.ts`, add before the closing `}`:

```typescript
case "conversation.sync":
  this.ctx.conversationStore.sync(command.conversations);
  break;

case "conversation.messageAppend":
  this.ctx.conversationStore.appendMessage(command.conversationId, command.message);
  break;

case "project.sync":
  this.ctx.projectStore.sync(command.projects);
  break;

case "ios.registerPush":
  // Acknowledge; Mac app handles pusher setup
  this.broadcast({ type: "ios.pushRegistered", apnsToken: command.apnsToken });
  logger.info("ws", `ios.registerPush: registered token for app ${command.appId}`);
  break;
```

- [ ] **Step 4: Verify no TypeScript errors**

```bash
cd /Users/shayco/Odyssey/sidecar && bun build src/index.ts --outdir /tmp/odyssey-build-check 2>&1 | head -30
```
Expected: clean build

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey && git add sidecar/src/ws-server.ts sidecar/src/index.ts sidecar/src/tools/tool-context.ts
git commit -m "feat(sidecar): wire conversation/project/push command handlers"
```

---

### Task 5: New REST Endpoints in `api-router.ts`

**Files:**
- Modify: `sidecar/src/api-router.ts`
- Test: `sidecar/test/api/http-api.test.ts` (extend)

- [ ] **Step 1: Add API tests for new endpoints**

Add to the existing `sidecar/test/api/http-api.test.ts`:

```typescript
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";

// In the test setup, create pre-populated stores:
const convStore = new ConversationStore();
convStore.sync([{
  id: "conv-1", topic: "Test Chat", lastMessageAt: "2026-04-13T10:00:00Z",
  lastMessagePreview: "hello", unread: false, participants: [],
  projectId: null, projectName: null, workingDirectory: null,
}]);
convStore.appendMessage("conv-1", {
  id: "msg-1", text: "Hello world", type: "text",
  senderParticipantId: null, timestamp: "2026-04-13T10:00:00Z", isStreaming: false,
});

const projStore = new ProjectStore();
projStore.sync([{ id: "proj-1", name: "MyApp", rootPath: "/Users/test/MyApp",
  icon: "folder", color: "blue", isPinned: true, pinnedAgentIds: [] }]);

// Tests:
test("GET /api/v1/conversations returns conversation list", async () => {
  const res = await fetch(`http://localhost:${TEST_HTTP_PORT}/api/v1/conversations`);
  expect(res.status).toBe(200);
  const body = await res.json() as any[];
  expect(body).toHaveLength(1);
  expect(body[0].id).toBe("conv-1");
});

test("GET /api/v1/conversations/:id/messages returns messages", async () => {
  const res = await fetch(`http://localhost:${TEST_HTTP_PORT}/api/v1/conversations/conv-1/messages`);
  expect(res.status).toBe(200);
  const body = await res.json() as any[];
  expect(body[0].text).toBe("Hello world");
});

test("GET /api/v1/conversations/:id/messages respects limit param", async () => {
  const res = await fetch(`http://localhost:${TEST_HTTP_PORT}/api/v1/conversations/conv-1/messages?limit=0`);
  expect(res.status).toBe(200);
  const body = await res.json() as any[];
  expect(body).toHaveLength(0);
});

test("GET /api/v1/projects returns project list", async () => {
  const res = await fetch(`http://localhost:${TEST_HTTP_PORT}/api/v1/projects`);
  expect(res.status).toBe(200);
  const body = await res.json() as any[];
  expect(body[0].name).toBe("MyApp");
});

test("GET /api/v1/conversations/missing/messages returns 404", async () => {
  const res = await fetch(`http://localhost:${TEST_HTTP_PORT}/api/v1/conversations/missing/messages`);
  expect(res.status).toBe(404);
});
```

- [ ] **Step 2: Add routes in `api-router.ts`**

Find `sidecar/src/api-router.ts` and add the new routes. Look for the pattern used by existing routes (likely a `router.get(...)` pattern). Add:

```typescript
// Conversations
router.get("/api/v1/conversations", (req) => {
  const conversations = ctx.conversationStore.listConversations();
  return new Response(JSON.stringify(conversations), {
    headers: { "Content-Type": "application/json" },
  });
});

router.get("/api/v1/conversations/:id/messages", (req) => {
  const { id } = req.params;
  const url = new URL(req.url);
  const limit = url.searchParams.get("limit");
  const before = url.searchParams.get("before") ?? undefined;
  const messages = ctx.conversationStore.getMessages(
    id,
    limit !== null ? parseInt(limit, 10) : undefined,
    before,
  );
  if (!ctx.conversationStore.listConversations().find(c => c.id === id) && messages.length === 0) {
    return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
  }
  return new Response(JSON.stringify(messages), {
    headers: { "Content-Type": "application/json" },
  });
});

// Projects
router.get("/api/v1/projects", (req) => {
  const projects = ctx.projectStore.list();
  return new Response(JSON.stringify(projects), {
    headers: { "Content-Type": "application/json" },
  });
});
```

> Note: The exact router API depends on how `api-router.ts` is structured. Read the file first to match the existing pattern.

- [ ] **Step 3: Run API tests**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/api/http-api.test.ts
```
Expected: new tests PASS

- [ ] **Step 4: Commit**

```bash
cd /Users/shayco/Odyssey && git add sidecar/src/api-router.ts sidecar/test/api/http-api.test.ts
git commit -m "feat(sidecar): add /api/v1/conversations and /api/v1/projects REST endpoints"
```

---

### Task 6: Mac Swift — Push Conversation Sync on Sidecar Connect

**Files:**
- Modify: `Odyssey/Services/SidecarManager.swift`
- Modify: `Odyssey/Services/SidecarProtocol.swift`

- [ ] **Step 1: Add new command cases to `SidecarProtocol.swift`**

In `Odyssey/Services/SidecarProtocol.swift`, find the `SidecarCommand` enum and add:

```swift
// In SidecarCommand enum:
case conversationSync(conversations: [ConversationSummaryWire])
case conversationMessageAppend(conversationId: UUID, message: MessageWire)
case projectSync(projects: [ProjectSummaryWire])

// Wire types (add as structs in the same file or a new file):
struct ConversationSummaryWire: Codable {
    let id: String
    let topic: String
    let lastMessageAt: String
    let lastMessagePreview: String
    let unread: Bool
    let participants: [ParticipantWire]
    let projectId: String?
    let projectName: String?
    let workingDirectory: String?
}

struct MessageWire: Codable {
    let id: String
    let text: String
    let type: String
    let senderParticipantId: String?
    let timestamp: String
    let isStreaming: Bool
    let toolName: String?
    let toolOutput: String?
    let thinkingText: String?
}

struct ParticipantWire: Codable {
    let id: String
    let displayName: String
    let isAgent: Bool
    let isLocal: Bool
}

struct ProjectSummaryWire: Codable {
    let id: String
    let name: String
    let rootPath: String
    let icon: String
    let color: String
    let isPinned: Bool
    let pinnedAgentIds: [String]
}
```

In `SidecarCommand.encodeToJSON()`, add encoding cases:

```swift
case .conversationSync(let conversations):
    let payload: [String: Any] = ["type": "conversation.sync", "conversations": try encodeArray(conversations)]
    return try JSONSerialization.data(withJSONObject: payload)

case .conversationMessageAppend(let conversationId, let message):
    let payload: [String: Any] = [
        "type": "conversation.messageAppend",
        "conversationId": conversationId.uuidString,
        "message": try encodeObject(message),
    ]
    return try JSONSerialization.data(withJSONObject: payload)

case .projectSync(let projects):
    let payload: [String: Any] = ["type": "project.sync", "projects": try encodeArray(projects)]
    return try JSONSerialization.data(withJSONObject: payload)
```

> Note: Look at existing encode patterns in `encodeToJSON()` to match the exact helper used (e.g., `JSONEncoder().encode()`).

- [ ] **Step 2: Add `pushConversationSync()` to `SidecarManager.swift`**

Add this method to `SidecarManager`:

```swift
/// Called when sidecar connects — pushes last 50 conversations and all projects to sidecar
func pushConversationSync(modelContext: ModelContext) async {
    do {
        let convDescriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        var convFetch = convDescriptor
        convFetch.fetchLimit = 50
        let conversations = try modelContext.fetch(convFetch)
        
        let convWires = conversations.map { conv -> ConversationSummaryWire in
            let lastMsg = conv.messages.sorted { $0.timestamp > $1.timestamp }.first
            return ConversationSummaryWire(
                id: conv.id.uuidString,
                topic: conv.topic ?? "Untitled",
                lastMessageAt: ISO8601DateFormatter().string(from: conv.updatedAt ?? Date()),
                lastMessagePreview: lastMsg?.text?.prefix(100).description ?? "",
                unread: false,
                participants: conv.participants.map { p in
                    ParticipantWire(
                        id: p.id.uuidString,
                        displayName: p.displayName,
                        isAgent: p.typeKind == "agentSession",
                        isLocal: p.isLocalParticipant
                    )
                },
                projectId: conv.project?.id.uuidString,
                projectName: conv.project?.name,
                workingDirectory: nil
            )
        }
        
        try await send(.conversationSync(conversations: convWires))
        
        let projDescriptor = FetchDescriptor<Project>()
        let projects = try modelContext.fetch(projDescriptor)
        let projWires = projects.map { proj in
            ProjectSummaryWire(
                id: proj.id.uuidString,
                name: proj.name,
                rootPath: proj.rootPath ?? "",
                icon: proj.icon ?? "folder",
                color: proj.colorName ?? "blue",
                isPinned: proj.isPinned,
                pinnedAgentIds: proj.pinnedAgentIds?.map(\.uuidString) ?? []
            )
        }
        try await send(.projectSync(projects: projWires))
    } catch {
        Log.sidecar.warning("pushConversationSync failed: \(error.localizedDescription, privacy: .public)")
    }
}
```

> Note: Adjust field names to match the actual `Conversation` and `Project` SwiftData models. Read `Odyssey/Models/Conversation.swift` and `Odyssey/Models/Project.swift` first.

- [ ] **Step 3: Call `pushConversationSync` when sidecar connects**

In `Odyssey/App/AppState.swift`, find `handleEvent` for `.connected` and add the push call. Look for where `.connected` is handled (likely sets `sidecarStatus = .connected`) and add:

```swift
case .connected:
    sidecarStatus = .connected
    // existing code...
    Task { @MainActor in
        await sidecarManager.pushConversationSync(modelContext: modelContext)
    }
```

- [ ] **Step 4: Build macOS target to verify no compile errors**

```bash
cd /Users/shayco/Odyssey && xcodebuild build -scheme Odyssey -destination 'platform=macOS' -quiet 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey && git add Odyssey/Services/SidecarProtocol.swift Odyssey/Services/SidecarManager.swift Odyssey/App/AppState.swift
git commit -m "feat(mac): push conversation+project snapshots to sidecar on connect"
```

---

### Task 7: Mac Swift — Push Message Append After Agent Response + User Send

**Files:**
- Modify: `Odyssey/App/AppState.swift`

- [ ] **Step 1: Add `pushMessageAppend` helper to `SidecarManager.swift`**

```swift
func pushMessageAppend(conversationId: UUID, message: ConversationMessage) async {
    guard let text = message.text else { return }
    let wire = MessageWire(
        id: message.id.uuidString,
        text: text,
        type: message.messageType.rawValue,
        senderParticipantId: message.senderParticipant?.id.uuidString,
        timestamp: ISO8601DateFormatter().string(from: message.timestamp),
        isStreaming: false,
        toolName: message.toolName,
        toolOutput: message.toolOutput,
        thinkingText: nil
    )
    try? await send(.conversationMessageAppend(conversationId: conversationId, message: wire))
}
```

- [ ] **Step 2: Call after `session.result` event in `AppState.handleEvent`**

Find where `SidecarEvent.sessionResult` (or `.result`) is handled in `AppState.handleEvent`. After persisting the message to SwiftData, add:

```swift
// After SwiftData persist:
if let conversationId = conversationIdForSession[event.sessionId] {
    Task {
        await sidecarManager.pushMessageAppend(conversationId: conversationId, message: savedMessage)
    }
}
```

- [ ] **Step 3: Call after user sends a message**

Find where user messages are saved to SwiftData (likely in `ChatView` or `AppState.sendMessage`). After save, add:

```swift
await sidecarManager.pushMessageAppend(conversationId: conversationId, message: userMessage)
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild build -scheme Odyssey -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey && git add Odyssey/Services/SidecarManager.swift Odyssey/App/AppState.swift
git commit -m "feat(mac): push conversation.messageAppend after agent result and user send"
```

---

### Task 8: XcodeGen iOS Target Setup

**Files:**
- Modify: `project.yml`
- Create: `OdysseyiOS/Resources/Info.plist`
- Create: `OdysseyiOS/Resources/OdysseyiOS.entitlements`
- Create: `OdysseyiOS/` directory structure

- [ ] **Step 1: Create iOS directory structure**

```bash
mkdir -p /Users/shayco/Odyssey/OdysseyiOS/Resources
mkdir -p /Users/shayco/Odyssey/OdysseyiOS/App
mkdir -p /Users/shayco/Odyssey/OdysseyiOS/Services
mkdir -p /Users/shayco/Odyssey/OdysseyiOS/Views
```

- [ ] **Step 2: Create `OdysseyiOS.entitlements`**

```xml
<!-- OdysseyiOS/Resources/OdysseyiOS.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Create `Info.plist`**

```xml
<!-- OdysseyiOS/Resources/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Odyssey</string>
    <key>CFBundleDisplayName</key><string>Odyssey</string>
    <key>CFBundleIdentifier</key><string>com.odyssey.app.ios</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>NSBonjourServices</key>
    <array><string>_odyssey._tcp</string></array>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Odyssey uses your local network to connect to your Mac's AI agents.</string>
    <key>NSCameraUsageDescription</key>
    <string>Scan the pairing QR code displayed on your Mac.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSExceptionDomains</key>
        <dict>
            <key>local</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key><false/>
                <key>NSRequiresCertificateTransparency</key><false/>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
```

- [ ] **Step 4: Add iOS target to `project.yml`**

Read `project.yml` first, then add to the `targets:` section:

```yaml
OdysseyiOS:
  type: application
  platform: iOS
  deploymentTarget: "17.0"
  settings:
    base:
      PRODUCT_BUNDLE_IDENTIFIER: com.odyssey.app.ios
      INFOPLIST_FILE: OdysseyiOS/Resources/Info.plist
      CODE_SIGN_ENTITLEMENTS: OdysseyiOS/Resources/OdysseyiOS.entitlements
      SWIFT_VERSION: "5.9"
  sources:
    - OdysseyiOS
  dependencies:
    - package: OdysseyCore
```

Also add `OdysseyCore` local package to the `packages:` section if not already there (added in Phase 3):
```yaml
packages:
  OdysseyCore:
    path: Packages/OdysseyCore
```

- [ ] **Step 5: Create a placeholder App entry point to allow xcodegen to succeed**

```swift
// OdysseyiOS/App/OdysseyiOSApp.swift (placeholder — full version in Phase 4b)
import SwiftUI

@main
struct OdysseyiOSApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Odyssey iOS — coming soon")
        }
    }
}
```

- [ ] **Step 6: Regenerate Xcode project**

```bash
cd /Users/shayco/Odyssey && xcodegen generate
```
Expected: `⚙️  Generating plists...` / `⚙️  Generating project...` / `✅  Created project at ...`

- [ ] **Step 7: Verify iOS Simulator build**

```bash
xcodebuild build -scheme OdysseyiOS -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
cd /Users/shayco/Odyssey && git add project.yml OdysseyiOS/ && git commit -m "feat(ios): add OdysseyiOS Xcode target with Info.plist and entitlements"
```
