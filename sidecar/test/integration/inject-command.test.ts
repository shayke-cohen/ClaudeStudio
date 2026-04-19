/**
 * Integration tests for the nostr.injectCommand WS handler.
 *
 * nostr.injectCommand allows the Swift NostrRelayManager to inject a
 * pre-decrypted SidecarCommand into the sidecar as if it arrived locally.
 *
 * Usage: bun test test/integration/inject-command.test.ts
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
import { DelegationStore } from "../../src/stores/delegation-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig } from "../../src/types.js";
import { wsConnectDirect } from "../helpers.js";

const WS_PORT = 29849 + Math.floor(Math.random() * 1000);
let wsServer: WsServer;
let sessionCreateCalls: Array<{ id: string; config: any }>;
let sessionMessageCalls: Array<{ id: string; text: string }>;

const mockSessionManager = {
  createSession: async (id: string, config: any) => {
    sessionCreateCalls.push({ id, config });
  },
  sendMessage: async (id: string, text: string) => {
    sessionMessageCalls.push({ id, text });
  },
  resumeSession: async () => {},
  bulkResume: async () => {},
  updateSessionMode: () => {},
  forkSession: async () => {},
  pauseSession: async () => {},
  updateSessionCwd: () => {},
} as any;

beforeAll(() => {
  sessionCreateCalls = [];
  sessionMessageCalls = [];

  const ctx: ToolContext = {
    blackboard: new BlackboardStore(`inject-test-${Date.now()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore: new ConversationStore(),
    projectStore: new ProjectStore(),
    delegation: new DelegationStore(),
    taskBoard: new TaskBoardStore(`inject-test-${Date.now()}`),
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

function wsConnect() { return wsConnectDirect(WS_PORT); }

describe("nostr.injectCommand", () => {
  test("injects session.create and calls sessionManager.createSession", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const conversationId = `inject-test-${Date.now()}`;
      ws.send({
        type: "nostr.injectCommand",
        command: {
          type: "session.create",
          conversationId,
          agentConfig: {
            provider: "mock",
            model: "mock",
            systemPrompt: "You are a test agent",
            name: "TestAgent",
            skills: [],
            mcpServers: [],
          },
        },
      });

      // Allow dispatch to settle
      await new Promise((r) => setTimeout(r, 100));
      const created = sessionCreateCalls.find((c) => c.id === conversationId);
      expect(created).toBeDefined();
      expect(created?.id).toBe(conversationId);
    } finally {
      ws.close();
    }
  });

  test("injects session.message and calls sessionManager.sendMessage", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const sessionId = `inject-msg-${Date.now()}`;
      ws.send({
        type: "nostr.injectCommand",
        command: {
          type: "session.message",
          sessionId,
          text: "Hello from Nostr relay",
        },
      });

      await new Promise((r) => setTimeout(r, 100));
      const sent = sessionMessageCalls.find((c) => c.id === sessionId);
      expect(sent).toBeDefined();
      expect(sent?.text).toBe("Hello from Nostr relay");
    } finally {
      ws.close();
    }
  });

  test("unknown inner command type does not crash the server", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "nostr.injectCommand",
        command: { type: "totally.unknown.command" },
      });

      // Server must stay alive and respond to subsequent commands
      await new Promise((r) => setTimeout(r, 150));
      ws.send({ type: "nostr.injectCommand", command: { type: "totally.unknown.command" } });
      await new Promise((r) => setTimeout(r, 100));
      expect(ws.ws.readyState).toBe(WebSocket.OPEN);
    } finally {
      ws.close();
    }
  });
});
