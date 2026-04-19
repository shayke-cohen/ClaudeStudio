/**
 * API tests for conversation.evaluate command routing over WebSocket.
 *
 * Boots a real WsServer with a mock SessionManager that has evaluateSession
 * returning a canned result. Verifies that sending conversation.evaluate
 * over the WebSocket produces conversation.idle and conversation.idleResult
 * broadcast events received by the connected client.
 *
 * Usage: ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) bun test test/api/idle-detection-api.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { WsServer } from "../../src/ws-server.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig } from "../../src/types.js";
import { wsConnectDirect } from "../helpers.js";

const WS_PORT = 29849 + Math.floor(Math.random() * 1000);
let wsServer: WsServer;

// Track evaluateSession calls so we can assert routing
const evalCalls: Array<{ sessionId: string; prompt: string }> = [];

const mockSessionManager = {
  createSession: async () => {},
  sendMessage: async () => {},
  resumeSession: async () => {},
  bulkResume: async () => {},
  updateSessionMode: () => {},
  forkSession: async () => {},
  pauseSession: async () => {},
  // evaluateSession returns a canned "complete" result
  evaluateSession: async (sessionId: string, prompt: string) => {
    evalCalls.push({ sessionId, prompt });
    return { status: "complete" as const, reason: "Goal was achieved in testing" };
  },
} as any;

beforeAll(() => {
  const ctx: ToolContext = {
    blackboard: new BlackboardStore(`idle-api-test-${Date.now()}`),
    sessions: new SessionRegistry(),
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
    broadcast: () => {},
    spawnSession: async (sid) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
  };

  wsServer = new WsServer(WS_PORT, mockSessionManager, ctx);
});

afterAll(() => {
  wsServer.close();
});

function wsConnect(timeoutMs = 5000) {
  return wsConnectDirect(WS_PORT, timeoutMs);
}

// ─── conversation.evaluate routing ──────────────────────────────────

describe("conversation.evaluate — WebSocket command routing", () => {
  test("sends conversation.evaluate, receives conversation.idle event", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "conversation.evaluate",
        conversationId: "api-test-conv-1",
        sessionIds: ["api-sess-1"],
      });

      const idleEvent = await ws.waitFor((m) => m.type === "conversation.idle", 3000);
      expect(idleEvent.type).toBe("conversation.idle");
      expect((idleEvent as any).conversationId).toBe("api-test-conv-1");
    } finally {
      ws.close();
    }
  });

  test("sends conversation.evaluate, receives conversation.idleResult event", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "conversation.evaluate",
        conversationId: "api-test-conv-2",
        sessionIds: ["api-sess-2"],
      });

      const resultEvent = await ws.waitFor((m) => m.type === "conversation.idleResult", 3000);
      expect(resultEvent.type).toBe("conversation.idleResult");
      expect((resultEvent as any).conversationId).toBe("api-test-conv-2");
      expect((resultEvent as any).status).toBe("complete");
      expect((resultEvent as any).reason).toBe("Goal was achieved in testing");
    } finally {
      ws.close();
    }
  });

  test("conversation.idle is received before conversation.idleResult", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "conversation.evaluate",
        conversationId: "api-order-test",
        sessionIds: ["ord-sess"],
      });

      const collected = await ws.collectUntil((m) => m.type === "conversation.idleResult", 3000);
      const evalEvents = collected.filter(
        (e) => e.type === "conversation.idle" || e.type === "conversation.idleResult",
      );

      expect(evalEvents.length).toBeGreaterThanOrEqual(2);
      const idleIdx = evalEvents.findIndex((e) => e.type === "conversation.idle");
      const resultIdx = evalEvents.findIndex((e) => e.type === "conversation.idleResult");
      expect(idleIdx).toBeGreaterThanOrEqual(0);
      expect(resultIdx).toBeGreaterThan(idleIdx);
    } finally {
      ws.close();
    }
  });

  test("coordinatorSessionId is forwarded to evaluateSession", async () => {
    const prevCount = evalCalls.length;
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "conversation.evaluate",
        conversationId: "api-coord-test",
        coordinatorSessionId: "coordinator-sess-id",
        sessionIds: ["other-sess"],
      });

      await ws.waitFor((m) => m.type === "conversation.idleResult", 3000);

      const newCalls = evalCalls.slice(prevCount);
      // With coordinatorSessionId, only the coordinator should be evaluated
      expect(newCalls.length).toBe(1);
      expect(newCalls[0].sessionId).toBe("coordinator-sess-id");
    } finally {
      ws.close();
    }
  });

  test("goal is passed through to evaluateSession prompt", async () => {
    const prevCount = evalCalls.length;
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "conversation.evaluate",
        conversationId: "api-goal-test",
        sessionIds: ["goal-sess"],
        goal: "build a working prototype",
      });

      await ws.waitFor((m) => m.type === "conversation.idleResult", 3000);

      const newCalls = evalCalls.slice(prevCount);
      expect(newCalls.length).toBeGreaterThan(0);
      expect(newCalls[0].prompt).toContain("build a working prototype");
    } finally {
      ws.close();
    }
  });

  test("events are broadcast to all connected clients", async () => {
    const ws1 = await wsConnect();
    const ws2 = await wsConnect();
    try {
      await ws1.waitFor((m) => m.type === "sidecar.ready");
      await ws2.waitFor((m) => m.type === "sidecar.ready");

      // ws1 sends the command
      ws1.send({
        type: "conversation.evaluate",
        conversationId: "api-broadcast-test",
        sessionIds: ["broadcast-sess"],
      });

      // Both clients should receive conversation.idleResult
      const [r1, r2] = await Promise.all([
        ws1.waitFor((m) => m.type === "conversation.idleResult", 3000),
        ws2.waitFor((m) => m.type === "conversation.idleResult", 3000),
      ]);

      expect((r1 as any).conversationId).toBe("api-broadcast-test");
      expect((r2 as any).conversationId).toBe("api-broadcast-test");
    } finally {
      ws1.close();
      ws2.close();
    }
  });
});
