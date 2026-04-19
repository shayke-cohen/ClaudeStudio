/**
 * API tests for slash command side-effects visible through the REST layer.
 *
 * Slash commands arrive over WebSocket, but their effects land in shared stores
 * that the REST API reads from. These tests verify:
 * - GET /sessions/:id reflects sessions with updated model after updateConfig
 * - GET /sessions returns the full list unaffected after clearMessages
 * - Model / effort updates only change AgentConfig, not SessionState
 * - conversation.clear leaves session state intact (messages are sidecar-internal)
 *
 * Usage: bun test test/api/slash-commands-api.test.ts
 */
import { describe, test, expect, afterEach } from "bun:test";
import { handleApiRequest } from "../../src/api-router.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { SseManager } from "../../src/sse-manager.js";
import { WebhookManager } from "../../src/webhook-manager.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import { makeAgentConfig } from "../helpers.js";
import type { ApiContext, SidecarEvent } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";

const BASE = "http://localhost/api/v1";

const activeSseManagers: SseManager[] = [];

function makeCtx(): { ctx: ApiContext; sessions: SessionRegistry } {
  const sessions = new SessionRegistry();
  const sseManager = new SseManager();

  const toolCtx: ToolContext = {
    blackboard: new BlackboardStore(`slash-api-${Date.now()}`),
    sessions,
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore: new ConversationStore(),
    projectStore: new ProjectStore(),
    nostrTransport: new NostrTransport(() => {}),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast: (event: SidecarEvent) => sseManager.broadcast(event),
    agentDefinitions: new Map(),
    spawnSession: async (id) => ({ sessionId: id }),
  };

  const ctx: ApiContext = {
    sessionManager: {
      listSessions: () => sessions.list(),
      pauseSession: async () => {},
      resumeSession: async () => {},
      spawnAutonomous: async (id) => ({ sessionId: id }),
    } as any,
    toolCtx,
    sseManager,
    webhookManager: new WebhookManager(),
  };

  activeSseManagers.push(sseManager);
  return { ctx, sessions };
}

afterEach(() => {
  while (activeSseManagers.length > 0) activeSseManagers.pop()?.close();
});

// ─── GET /sessions/:id after model update ────────────────────────────

describe("API: GET /sessions/:id — session state after model update", () => {
  test("returns 200 with correct agentName after model updateConfig", async () => {
    const { ctx, sessions } = makeCtx();
    sessions.create("sess-model", makeAgentConfig({ name: "ModelAgent", model: "claude-haiku-4-5-20251001" }));
    sessions.updateConfig("sess-model", { model: "claude-opus-4-7" });

    const res = await handleApiRequest(new Request(`${BASE}/sessions/sess-model`), ctx);
    expect(res?.status).toBe(200);
    const body = await res?.json() as any;
    expect(body.id).toBe("sess-model");
    expect(body.agentName).toBe("ModelAgent");
  });

  test("model change does not alter SessionState fields (status, tokenCount)", async () => {
    const { ctx, sessions } = makeCtx();
    sessions.create("sess-state", makeAgentConfig({ name: "StateAgent" }));
    sessions.update("sess-state", { tokenCount: 99, status: "active" });
    sessions.updateConfig("sess-state", { model: "claude-opus-4-7" });

    const res = await handleApiRequest(new Request(`${BASE}/sessions/sess-state`), ctx);
    const body = await res?.json() as any;
    expect(body.tokenCount).toBe(99);
    expect(body.status).toBe("active");
  });

  test("returns 404 for session that never existed", async () => {
    const { ctx } = makeCtx();
    const res = await handleApiRequest(new Request(`${BASE}/sessions/ghost`), ctx);
    expect(res?.status).toBe(404);
  });
});

// ─── GET /sessions/:id after effort update ───────────────────────────

describe("API: GET /sessions/:id — session state after effort update", () => {
  test("effort update does not remove the session from the registry", async () => {
    const { ctx, sessions } = makeCtx();
    sessions.create("sess-effort", makeAgentConfig({ name: "EffortAgent" }));
    sessions.updateConfig("sess-effort", { maxThinkingTokens: 32_000 });

    const res = await handleApiRequest(new Request(`${BASE}/sessions/sess-effort`), ctx);
    expect(res?.status).toBe(200);
    const body = await res?.json() as any;
    expect(body.id).toBe("sess-effort");
  });

  test("effort update does not affect a different session", async () => {
    const { ctx, sessions } = makeCtx();
    sessions.create("sess-a", makeAgentConfig({ name: "AgentA" }));
    sessions.create("sess-b", makeAgentConfig({ name: "AgentB" }));
    sessions.updateConfig("sess-a", { maxThinkingTokens: 100_000 });

    const resB = await handleApiRequest(new Request(`${BASE}/sessions/sess-b`), ctx);
    const bodyB = await resB?.json() as any;
    expect(bodyB.id).toBe("sess-b");
    expect(bodyB.agentName).toBe("AgentB");
  });
});

// ─── GET /sessions list unaffected by conversation.clear ─────────────

describe("API: GET /sessions — list unaffected by conversation clear", () => {
  test("session list is unchanged after clearMessages on conversation store", async () => {
    const { ctx, sessions } = makeCtx();
    sessions.create("sess-1", makeAgentConfig({ name: "Agent1" }));
    sessions.create("sess-2", makeAgentConfig({ name: "Agent2" }));

    // Simulate conversation.clear
    ctx.toolCtx.conversationStore.appendMessage("conv-x", {
      id: "m1", text: "hello", type: "text",
      senderParticipantId: null,
      timestamp: new Date().toISOString(),
      isStreaming: false,
    });
    ctx.toolCtx.conversationStore.clearMessages("conv-x");

    const res = await handleApiRequest(new Request(`${BASE}/sessions`), ctx);
    expect(res?.status).toBe(200);
    const body = await res?.json() as any;
    expect(body.sessions).toHaveLength(2);
    expect(body.sessions.map((s: any) => s.agentName).sort()).toEqual(["Agent1", "Agent2"]);
  });
});

// ─── AgentConfig.model is updated after updateConfig ─────────────────

describe("API: AgentConfig — model persists after updateConfig", () => {
  test("getConfig returns updated model after updateConfig", () => {
    const { sessions } = makeCtx();
    sessions.create("sess-x", makeAgentConfig({ name: "X", model: "claude-haiku-4-5-20251001" }));
    sessions.updateConfig("sess-x", { model: "claude-sonnet-4-6" });
    expect(sessions.getConfig("sess-x")?.model).toBe("claude-sonnet-4-6");
  });

  test("getConfig returns updated maxThinkingTokens after effort update", () => {
    const { sessions } = makeCtx();
    sessions.create("sess-x", makeAgentConfig({ name: "X" }));
    sessions.updateConfig("sess-x", { maxThinkingTokens: 8_000 });
    expect(sessions.getConfig("sess-x")?.maxThinkingTokens).toBe(8_000);
  });
});
