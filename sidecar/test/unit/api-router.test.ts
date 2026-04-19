/**
 * Unit tests for api-router.ts covering route matching and error shapes
 * without booting a real HTTP server. Exercises handleApiRequest directly.
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { handleApiRequest } from "../../src/api-router.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { DelegationStore } from "../../src/stores/delegation-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import { SseManager } from "../../src/sse-manager.js";
import { WebhookManager } from "../../src/webhook-manager.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { ApiContext, AgentConfig } from "../../src/types.js";

function buildApiCtx(): { ctx: ApiContext; sseManager: SseManager } {
  const toolCtx: ToolContext = {
    blackboard: new BlackboardStore(`api-router-${Date.now()}-${Math.random()}`),
    taskBoard: new TaskBoardStore(`api-router-${Date.now()}-${Math.random()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore: new ConversationStore(),
    projectStore: new ProjectStore(),
    delegation: new DelegationStore(),
    nostrTransport: new NostrTransport(() => {}),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast: () => {},
    spawnSession: async (sid) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
  };
  const mockSessionManager = {
    listSessions: () => Array.from(toolCtx.sessions.list()),
    sendMessage: async () => {},
    pauseSession: async () => {},
    resumeSession: async () => {},
    forkSession: async () => {},
    spawnAutonomous: async (id: string) => ({ sessionId: id }),
    updateSessionMode: () => {},
    answerQuestion: async () => false,
    answerConfirmation: async () => false,
    buildQueryOptionsForTesting: () => ({}),
    updateSessionCwd: () => {},
    bulkResume: async () => {},
  } as any;

  const sseManager = new SseManager();
  return {
    sseManager,
    ctx: {
      toolCtx,
      sessionManager: mockSessionManager,
      sseManager,
      webhookManager: new WebhookManager(),
    },
  };
}

async function get(path: string, ctx: ApiContext): Promise<{ status: number; body: any }> {
  const res = await handleApiRequest(new Request(`http://test${path}`), ctx);
  if (!res) return { status: 0, body: null };
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}
async function post(path: string, body: unknown, ctx: ApiContext): Promise<{ status: number; body: any }> {
  const res = await handleApiRequest(
    new Request(`http://test${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }),
    ctx,
  );
  if (!res) return { status: 0, body: null };
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

describe("api-router basics", () => {
  let ctx: ApiContext;
  let sseManager: SseManager;

  beforeEach(() => {
    const built = buildApiCtx();
    ctx = built.ctx;
    sseManager = built.sseManager;
  });

  test("returns null for non /api/v1 paths (fallthrough)", async () => {
    const res = await handleApiRequest(new Request("http://test/health"), ctx);
    expect(res).toBeNull();
  });

  test("OPTIONS preflight returns CORS headers", async () => {
    const res = await handleApiRequest(
      new Request("http://test/api/v1/sessions", { method: "OPTIONS" }),
      ctx,
    );
    expect(res).not.toBeNull();
    expect(res!.status).toBe(200);
    expect(res!.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(res!.headers.get("Access-Control-Allow-Methods")).toContain("POST");
  });

  test("unknown /api/v1 path returns 404 not_found", async () => {
    const { status, body } = await get("/api/v1/does-not-exist", ctx);
    expect(status).toBe(404);
    expect(body.error).toBe("not_found");
  });

  test("GET /api/v1/agents returns empty list when none registered", async () => {
    const { status, body } = await get("/api/v1/agents", ctx);
    expect(status).toBe(200);
    expect(body.agents).toEqual([]);
  });

  test("GET /api/v1/agents/:name returns 404 when missing", async () => {
    const { status, body } = await get("/api/v1/agents/Ghost", ctx);
    expect(status).toBe(404);
    expect(body.error).toBe("agent_not_found");
  });

  test("GET /api/v1/agents/:name returns config when registered", async () => {
    ctx.toolCtx.agentDefinitions.set("Coder", {
      name: "Coder",
      systemPrompt: "code",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/tmp",
      skills: [],
    });
    const { status, body } = await get("/api/v1/agents/Coder", ctx);
    expect(status).toBe(200);
    expect(body.name).toBe("Coder");
    expect(body.provider).toBe("claude");
  });

  test("GET /api/v1/sessions returns list", async () => {
    const { status, body } = await get("/api/v1/sessions", ctx);
    expect(status).toBe(200);
    expect(body.sessions).toEqual([]);
  });

  test("GET /api/v1/sessions/:id returns 404 when missing", async () => {
    const { status, body } = await get("/api/v1/sessions/ghost", ctx);
    expect(status).toBe(404);
    expect(body.error).toBe("session_not_found");
  });

  test("POST /api/v1/sessions missing agentName returns 400", async () => {
    const { status, body } = await post("/api/v1/sessions", { message: "hi" }, ctx);
    expect(status).toBe(400);
    expect(body.error).toBe("invalid_request");
    expect(body.message).toContain("agentName");
  });

  test("POST /api/v1/sessions missing message returns 400", async () => {
    const { status, body } = await post("/api/v1/sessions", { agentName: "Coder" }, ctx);
    expect(status).toBe(400);
    expect(body.error).toBe("invalid_request");
    expect(body.message).toContain("message");
  });

  test("POST /api/v1/sessions unknown agent returns 404", async () => {
    const { status, body } = await post("/api/v1/sessions", { agentName: "Ghost", message: "hi" }, ctx);
    expect(status).toBe(404);
    expect(body.error).toBe("agent_not_found");
  });

  test("POST /api/v1/sessions with malformed body returns 400", async () => {
    const res = await handleApiRequest(
      new Request("http://test/api/v1/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{not json",
      }),
      ctx,
    );
    expect(res!.status).toBe(400);
    const body = await res!.json();
    expect((body as any).error).toBe("invalid_request");
  });

  test("POST /api/v1/tasks creates task and GET lists it", async () => {
    const created = await post(
      "/api/v1/tasks",
      { title: "Do thing", createdBy: "user" },
      ctx,
    );
    expect(created.status).toBe(201);
    expect(created.body.title).toBe("Do thing");

    const listed = await get("/api/v1/tasks", ctx);
    expect(listed.status).toBe(200);
    expect(listed.body.tasks).toHaveLength(1);
    expect(listed.body.tasks[0].title).toBe("Do thing");
  });

  test("PATCH /api/v1/tasks/:id not found returns 404", async () => {
    const res = await handleApiRequest(
      new Request("http://test/api/v1/tasks/ghost", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: "done" }),
      }),
      ctx,
    );
    expect(res!.status).toBe(404);
  });

  test("GET /api/v1/peers returns list", async () => {
    const { status, body } = await get("/api/v1/peers", ctx);
    expect(status).toBe(200);
    expect(Array.isArray(body.peers ?? [])).toBe(true);
  });

  test("GET /api/v1/workspaces returns list", async () => {
    const { status, body } = await get("/api/v1/workspaces", ctx);
    expect(status).toBe(200);
    expect(body.workspaces).toEqual([]);
  });

  test("GET /api/v1/conversations returns empty", async () => {
    const { status, body } = await get("/api/v1/conversations", ctx);
    expect(status).toBe(200);
    expect(body.conversations).toEqual([]);
  });

  test("GET /api/v1/projects returns empty", async () => {
    const { status, body } = await get("/api/v1/projects", ctx);
    expect(status).toBe(200);
    expect(body.projects).toEqual([]);
  });

  test("method mismatch: GET on POST-only route returns 404", async () => {
    const { status } = await get("/api/v1/messages/send", ctx);
    expect(status).toBe(404);
  });

  test("teardown SSE", () => {
    sseManager.close();
  });
});
