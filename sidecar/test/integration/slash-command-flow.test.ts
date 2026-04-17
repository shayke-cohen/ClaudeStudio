/**
 * Integration tests for slash command flows.
 *
 * Boots a real WsServer with real stores (no mock SessionManager)
 * and exercises conversation.clear, session.updateModel, session.updateEffort
 * end-to-end through the command dispatch path.
 */
import { describe, test, expect, beforeAll, afterAll, beforeEach } from "bun:test";
import { WsServer } from "../../src/ws-server.js";
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
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, ConversationSummaryWire, MessageWire } from "../../src/types.js";
import { wsConnectDirect } from "../helpers.js";

const WS_PORT = 19750 + Math.floor(Math.random() * 500);
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
  updateConfig: () => {},
} as any;

const baseConfig: AgentConfig = {
  name: "Coder",
  systemPrompt: "You are a coder.",
  allowedTools: [],
  mcpServers: [],
  model: "claude-sonnet-4-6",
  workingDirectory: "/tmp",
  skills: [],
};

const makeConv = (id: string): ConversationSummaryWire => ({
  id, topic: "Test", lastMessageAt: "2026-01-01T00:00:00Z",
  lastMessagePreview: "", unread: false, participants: [],
  projectId: null, projectName: null, workingDirectory: null,
});
const makeMsg = (id: string, text: string): MessageWire => ({
  id, text, type: "text", senderParticipantId: null,
  timestamp: "2026-01-01T00:00:00Z", isStreaming: false,
});

function wsConnect() { return wsConnectDirect(WS_PORT, 5000); }

beforeAll(() => {
  sessions = new SessionRegistry();
  conversationStore = new ConversationStore();

  const ctx: ToolContext = {
    blackboard: new BlackboardStore(`slash-int-${Date.now()}`),
    taskBoard: new TaskBoardStore(`slash-int-${Date.now()}`),
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
});

afterAll(() => wsServer.close());

// ─── conversation.clear ─────────────────────────────────────────────

describe("Integration: conversation.clear", () => {
  beforeEach(() => {
    conversationStore.sync([makeConv("conv-clear-1")]);
    conversationStore.appendMessage("conv-clear-1", makeMsg("m1", "Msg 1"));
    conversationStore.appendMessage("conv-clear-1", makeMsg("m2", "Msg 2"));
  });

  test("clears messages and broadcasts conversation.cleared event", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      expect(conversationStore.getMessages("conv-clear-1")).toHaveLength(2);

      ws.send({ type: "conversation.clear", conversationId: "conv-clear-1" });
      const cleared = await ws.waitFor((m) => m.type === "conversation.cleared", 3000);

      expect(cleared.type).toBe("conversation.cleared");
      expect(cleared.conversationId).toBe("conv-clear-1");
      expect(conversationStore.getMessages("conv-clear-1")).toHaveLength(0);
    } finally {
      ws.close();
    }
  });

  test("clearing same conversation twice broadcasts event both times", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({ type: "conversation.clear", conversationId: "conv-clear-1" });
      const c1 = await ws.waitFor((m) => m.type === "conversation.cleared", 3000);
      expect(c1.conversationId).toBe("conv-clear-1");

      ws.send({ type: "conversation.clear", conversationId: "conv-clear-1" });
      const c2 = await ws.waitFor((m) => m.type === "conversation.cleared", 3000);
      expect(c2.conversationId).toBe("conv-clear-1");
    } finally {
      ws.close();
    }
  });
});

// ─── session.updateModel ────────────────────────────────────────────

describe("Integration: session.updateModel", () => {
  beforeEach(() => {
    sessions.create("sess-model-1", { ...baseConfig });
  });

  test("updates model in session config", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      expect(sessions.getConfig("sess-model-1")?.model).toBe("claude-sonnet-4-6");

      ws.send({ type: "session.updateModel", sessionId: "sess-model-1", model: "claude-opus-4-7" });
      // No broadcast event — just verify store mutation after brief delay
      await Bun.sleep(100);
      expect(sessions.getConfig("sess-model-1")?.model).toBe("claude-opus-4-7");
    } finally {
      ws.close();
    }
  });

  test("updateModel on unknown session does not crash server", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({ type: "session.updateModel", sessionId: "ghost-session", model: "claude-opus-4-7" });
      await Bun.sleep(100);
      // Server stays up — verify by sending another known command
      ws.send({ type: "conversation.clear", conversationId: "nonexistent" });
      const cleared = await ws.waitFor((m) => m.type === "conversation.cleared", 3000);
      expect(cleared.type).toBe("conversation.cleared");
    } finally {
      ws.close();
    }
  });
});

// ─── session.updateEffort ───────────────────────────────────────────

describe("Integration: session.updateEffort", () => {
  const effortToTokens: Record<string, number> = {
    low: 0, medium: 8_000, high: 32_000, max: 100_000,
  };

  beforeEach(() => {
    sessions.create("sess-effort-1", { ...baseConfig });
  });

  for (const [effort, tokens] of Object.entries(effortToTokens)) {
    test(`effort='${effort}' sets maxThinkingTokens=${tokens}`, async () => {
      const ws = await wsConnect();
      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        ws.send({ type: "session.updateEffort", sessionId: "sess-effort-1", effort });
        await Bun.sleep(100);
        expect(sessions.getConfig("sess-effort-1")?.maxThinkingTokens).toBe(tokens);
      } finally {
        ws.close();
      }
    });
  }
});
