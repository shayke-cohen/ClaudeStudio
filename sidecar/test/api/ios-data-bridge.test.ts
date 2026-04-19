import { describe, test, expect } from "bun:test";
import { handleApiRequest } from "../../src/api-router.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { SseManager } from "../../src/sse-manager.js";
import { WebhookManager } from "../../src/webhook-manager.js";
import type { ApiContext } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";

const BASE = "http://localhost/api/v1";

function makeContext() {
  const conversationStore = new ConversationStore();
  const projectStore = new ProjectStore();
  const sseManager = new SseManager();

  const toolCtx: ToolContext = {
    blackboard: new BlackboardStore(`ios-bridge-test-${Date.now()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    conversationStore,
    projectStore,
    broadcast: () => {},
    agentDefinitions: new Map(),
    spawnSession: async (sessionId) => ({ sessionId }),
  };

  const ctx: ApiContext = {
    sessionManager: {} as any,
    toolCtx,
    sseManager,
    webhookManager: new WebhookManager(),
  };

  return { ctx, conversationStore, projectStore };
}

// ─── GET /api/v1/conversations ───────────────────────────────────────

describe("GET /api/v1/conversations", () => {
  test("returns empty array when no conversations synced", async () => {
    const { ctx } = makeContext();
    const res = await handleApiRequest(
      new Request(`${BASE}/conversations`),
      ctx,
    );
    expect(res?.status).toBe(200);
    const body = (await res!.json()) as any;
    expect(body.conversations).toEqual([]);
  });

  test("returns synced conversations", async () => {
    const { ctx, conversationStore } = makeContext();
    conversationStore.sync([
      {
        id: "conv-1",
        topic: "Test Conversation",
        lastMessageAt: "2026-04-13T10:00:00Z",
        lastMessagePreview: "Hello world",
        unread: false,
        participants: [],
        projectId: null,
        projectName: null,
        workingDirectory: null,
      },
    ]);
    const res = await handleApiRequest(
      new Request(`${BASE}/conversations`),
      ctx,
    );
    expect(res?.status).toBe(200);
    const body = (await res!.json()) as any;
    expect(body.conversations).toHaveLength(1);
    expect(body.conversations[0].id).toBe("conv-1");
    expect(body.conversations[0].topic).toBe("Test Conversation");
  });
});

// ─── GET /api/v1/conversations/:id/messages ──────────────────────────

describe("GET /api/v1/conversations/:id/messages", () => {
  test("returns 404 for unknown conversation", async () => {
    const { ctx } = makeContext();
    const res = await handleApiRequest(
      new Request(`${BASE}/conversations/unknown-id/messages`),
      ctx,
    );
    expect(res?.status).toBe(404);
  });

  test("returns empty messages for known conversation with no messages", async () => {
    const { ctx, conversationStore } = makeContext();
    conversationStore.sync([
      {
        id: "conv-2",
        topic: "Another",
        lastMessageAt: "2026-04-13T10:00:00Z",
        lastMessagePreview: "",
        unread: false,
        participants: [],
        projectId: null,
        projectName: null,
        workingDirectory: null,
      },
    ]);
    const res = await handleApiRequest(
      new Request(`${BASE}/conversations/conv-2/messages`),
      ctx,
    );
    expect(res?.status).toBe(200);
    const body = (await res!.json()) as any;
    expect(body.messages).toEqual([]);
  });

  test("returns messages with limit support", async () => {
    const { ctx, conversationStore } = makeContext();
    conversationStore.sync([
      {
        id: "conv-3",
        topic: "Messages Test",
        lastMessageAt: "2026-04-13T10:00:00Z",
        lastMessagePreview: "",
        unread: false,
        participants: [],
        projectId: null,
        projectName: null,
        workingDirectory: null,
      },
    ]);
    for (let i = 0; i < 5; i++) {
      conversationStore.appendMessage("conv-3", {
        id: `msg-${i}`,
        text: `message ${i}`,
        type: "chat",
        senderParticipantId: null,
        timestamp: `2026-04-13T10:0${i}:00Z`,
        isStreaming: false,
      });
    }
    const res = await handleApiRequest(
      new Request(`${BASE}/conversations/conv-3/messages?limit=3`),
      ctx,
    );
    expect(res?.status).toBe(200);
    const body = (await res!.json()) as any;
    expect(body.messages).toHaveLength(3);
  });
});

// ─── GET /api/v1/projects ─────────────────────────────────────────────

describe("GET /api/v1/projects", () => {
  test("returns empty array when no projects synced", async () => {
    const { ctx } = makeContext();
    const res = await handleApiRequest(
      new Request(`${BASE}/projects`),
      ctx,
    );
    expect(res?.status).toBe(200);
    const body = (await res!.json()) as any;
    expect(body.projects).toEqual([]);
  });

  test("returns synced projects sorted by name", async () => {
    const { ctx, projectStore } = makeContext();
    projectStore.sync([
      { id: "p2", name: "Zeta", rootPath: "/z", icon: "folder", color: "blue", isPinned: false, pinnedAgentIds: [] },
      { id: "p1", name: "Alpha", rootPath: "/a", icon: "folder", color: "green", isPinned: false, pinnedAgentIds: [] },
    ]);
    const res = await handleApiRequest(
      new Request(`${BASE}/projects`),
      ctx,
    );
    expect(res?.status).toBe(200);
    const body = (await res!.json()) as any;
    expect(body.projects).toHaveLength(2);
    expect(body.projects[0].name).toBe("Alpha");
    expect(body.projects[1].name).toBe("Zeta");
  });

  test("pinned projects sort before unpinned", async () => {
    const { ctx, projectStore } = makeContext();
    projectStore.sync([
      { id: "p1", name: "Unpinned", rootPath: "/u", icon: "folder", color: "blue", isPinned: false, pinnedAgentIds: [] },
      { id: "p2", name: "Pinned", rootPath: "/p", icon: "star", color: "orange", isPinned: true, pinnedAgentIds: [] },
    ]);
    const res = await handleApiRequest(
      new Request(`${BASE}/projects`),
      ctx,
    );
    expect(res?.status).toBe(200);
    const body = (await res!.json()) as any;
    expect(body.projects[0].name).toBe("Pinned");
    expect(body.projects[1].name).toBe("Unpinned");
  });
});
