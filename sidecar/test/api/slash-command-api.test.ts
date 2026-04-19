/**
 * API tests for slash command WebSocket protocol messages.
 *
 * Tests conversation.clear, session.updateModel, session.updateEffort
 * commands via a real WsServer instance with mock SessionManager.
 *
 * Usage: ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) bun test test/api/slash-command-api.test.ts
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
import type { AgentConfig, ConversationSummaryWire, MessageWire } from "../../src/types.js";
import { wsConnectDirect } from "../helpers.js";

const WS_PORT = 19900 + Math.floor(Math.random() * 500);
let wsServer: WsServer;
let sessions: SessionRegistry;
let conversationStore: ConversationStore;

const mockSessionManager = {
  createSession: async () => {},
  sendMessage: async () => {},
  resumeSession: async () => {},
  bulkResume: async () => {},
  updateSessionMode: () => {},
  forkSession: async () => {},
  pauseSession: async () => {},
} as any;

const agentConfig: AgentConfig = {
  name: "APITestAgent",
  systemPrompt: "test",
  allowedTools: [],
  mcpServers: [],
  model: "claude-sonnet-4-6",
  workingDirectory: "/tmp",
  skills: [],
};

const makeConv = (id: string): ConversationSummaryWire => ({
  id, topic: "API test", lastMessageAt: "2026-01-01T00:00:00Z",
  lastMessagePreview: "", unread: false, participants: [],
  projectId: null, projectName: null, workingDirectory: null,
});
const makeMsg = (id: string): MessageWire => ({
  id, text: `msg-${id}`, type: "text", senderParticipantId: null,
  timestamp: "2026-01-01T00:00:00Z", isStreaming: false,
});

function wsConnect() { return wsConnectDirect(WS_PORT, 5000); }

beforeAll(() => {
  sessions = new SessionRegistry();
  conversationStore = new ConversationStore();

  const ctx: ToolContext = {
    blackboard: new BlackboardStore(`slash-api-${Date.now()}`),
    sessions,
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore,
    projectStore: new ProjectStore(),
    nostrTransport: new NostrTransport(() => {}),
    relayClient: { isConnected: () => false, connect: async () => {}, sendCommand: async () => ({}) } as any,
    broadcast: () => {},
    spawnSession: async (sid) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
  };

  wsServer = new WsServer(WS_PORT, mockSessionManager, ctx);

  // Seed: one conversation with 3 messages
  conversationStore.sync([makeConv("api-conv-1")]);
  for (let i = 1; i <= 3; i++) conversationStore.appendMessage("api-conv-1", makeMsg(`m${i}`));

  // Seed: one active session
  sessions.create("api-sess-1", { ...agentConfig });
});

afterAll(() => wsServer.close());

// ─── conversation.clear protocol ────────────────────────────────────

describe("API: conversation.clear command", () => {
  test("server responds with conversation.cleared event", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({ type: "conversation.clear", conversationId: "api-conv-1" });
      const evt = await ws.waitFor((m) => m.type === "conversation.cleared", 3000);
      expect(evt.conversationId).toBe("api-conv-1");
    } finally {
      ws.close();
    }
  });

  test("conversation.cleared event is broadcast to all connected clients", async () => {
    // Restore messages for this test
    conversationStore.appendMessage("api-conv-1", makeMsg("restore-1"));

    const ws1 = await wsConnect();
    const ws2 = await wsConnect();
    try {
      await ws1.waitFor((m) => m.type === "sidecar.ready");
      await ws2.waitFor((m) => m.type === "sidecar.ready");

      ws1.send({ type: "conversation.clear", conversationId: "api-conv-1" });
      const [evt1, evt2] = await Promise.all([
        ws1.waitFor((m) => m.type === "conversation.cleared", 3000),
        ws2.waitFor((m) => m.type === "conversation.cleared", 3000),
      ]);
      expect(evt1.conversationId).toBe("api-conv-1");
      expect(evt2.conversationId).toBe("api-conv-1");
    } finally {
      ws1.close();
      ws2.close();
    }
  });

  test("cleared event carries correct conversationId", async () => {
    conversationStore.sync([makeConv("api-conv-x"), makeConv("api-conv-y")]);
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({ type: "conversation.clear", conversationId: "api-conv-x" });
      const evt = await ws.waitFor((m) => m.type === "conversation.cleared", 3000);
      expect(evt.conversationId).toBe("api-conv-x");
    } finally {
      ws.close();
    }
  });
});

// ─── session.updateModel protocol ───────────────────────────────────

describe("API: session.updateModel command", () => {
  test("accepted without error — model stored in registry", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({ type: "session.updateModel", sessionId: "api-sess-1", model: "claude-opus-4-7" });
      await Bun.sleep(150);
      expect(sessions.getConfig("api-sess-1")?.model).toBe("claude-opus-4-7");
    } finally {
      ws.close();
    }
  });

  test("all three models accepted", async () => {
    const models = ["claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5"];
    for (const model of models) {
      sessions.create(`api-sess-model-${model}`, { ...agentConfig });
      const ws = await wsConnect();
      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        ws.send({ type: "session.updateModel", sessionId: `api-sess-model-${model}`, model });
        await Bun.sleep(100);
        expect(sessions.getConfig(`api-sess-model-${model}`)?.model).toBe(model);
      } finally {
        ws.close();
      }
    }
  });
});

// ─── session.updateEffort protocol ──────────────────────────────────

describe("API: session.updateEffort command", () => {
  const effortTable: Array<[string, number]> = [
    ["low", 0],
    ["medium", 8_000],
    ["high", 32_000],
    ["max", 100_000],
  ];

  for (const [effort, expectedTokens] of effortTable) {
    test(`effort='${effort}' → maxThinkingTokens=${expectedTokens}`, async () => {
      const sessId = `api-effort-${effort}`;
      sessions.create(sessId, { ...agentConfig });
      const ws = await wsConnect();
      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        ws.send({ type: "session.updateEffort", sessionId: sessId, effort });
        await Bun.sleep(100);
        expect(sessions.getConfig(sessId)?.maxThinkingTokens).toBe(expectedTokens);
      } finally {
        ws.close();
      }
    });
  }

  test("unknown effort string falls back to high (32000)", async () => {
    const sessId = "api-effort-unknown";
    sessions.create(sessId, { ...agentConfig });
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({ type: "session.updateEffort", sessionId: sessId, effort: "turbo" });
      await Bun.sleep(100);
      // fallback: effortToTokens[unknown] ?? 32_000
      expect(sessions.getConfig(sessId)?.maxThinkingTokens).toBe(32_000);
    } finally {
      ws.close();
    }
  });
});
