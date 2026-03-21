/**
 * API tests for the WebSocket command/event protocol.
 *
 * Boots a real WsServer and tests connect, ready event, command dispatch,
 * and event broadcasting. Uses mock SessionManager to avoid real Claude SDK calls.
 *
 * Usage: CLAUDPEER_DATA_DIR=/tmp/claudpeer-test-$(date +%s) bun test test/api/ws-protocol.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { WsServer } from "../../src/ws-server.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";

const WS_PORT = 19849 + Math.floor(Math.random() * 1000);
let wsServer: WsServer;
let ctx: ToolContext;
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
  forkSession: async () => "forked-id",
  pauseSession: async () => {},
} as any;

beforeAll(() => {
  sessionCreateCalls = [];
  sessionMessageCalls = [];

  ctx = {
    blackboard: new BlackboardStore(`ws-test-${Date.now()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    broadcast: () => {},
    spawnSession: async (sid, config, prompt, wait) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
  };

  wsServer = new WsServer(WS_PORT, mockSessionManager, ctx);
});

afterAll(() => {
  wsServer.close();
});

/**
 * Wrapper around WebSocket that buffers all incoming messages so we never
 * miss events due to race conditions between connect and listener setup.
 */
class BufferedWs {
  ws: WebSocket;
  buffer: any[] = [];
  private listeners: Array<(msg: any) => void> = [];

  constructor(ws: WebSocket) {
    this.ws = ws;
    ws.onmessage = (event: MessageEvent) => {
      const msg = JSON.parse(typeof event.data === "string" ? event.data : "{}");
      this.buffer.push(msg);
      for (const fn of this.listeners) fn(msg);
    };
  }

  send(data: any) {
    this.ws.send(JSON.stringify(data));
  }

  close() {
    this.ws.close();
  }

  waitFor(predicate: (msg: any) => boolean, timeoutMs = 5000): Promise<any> {
    const existing = this.buffer.find(predicate);
    if (existing) return Promise.resolve(existing);

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.listeners = this.listeners.filter((fn) => fn !== listener);
        reject(new Error("waitFor timeout"));
      }, timeoutMs);

      const listener = (msg: any) => {
        if (predicate(msg)) {
          clearTimeout(timer);
          this.listeners = this.listeners.filter((fn) => fn !== listener);
          resolve(msg);
        }
      };
      this.listeners.push(listener);
    });
  }

  collectNew(count: number, timeoutMs = 5000): Promise<any[]> {
    const startIdx = this.buffer.length;
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        resolve(this.buffer.slice(startIdx));
      }, timeoutMs);

      const listener = () => {
        if (this.buffer.length - startIdx >= count) {
          clearTimeout(timer);
          this.listeners = this.listeners.filter((fn) => fn !== listener);
          resolve(this.buffer.slice(startIdx, startIdx + count));
        }
      };
      this.listeners.push(listener);
    });
  }
}

function wsConnect(timeoutMs = 5000): Promise<BufferedWs> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${WS_PORT}`);
    const timer = setTimeout(() => reject(new Error("connect timeout")), timeoutMs);
    ws.onopen = () => {
      clearTimeout(timer);
      resolve(new BufferedWs(ws));
    };
    ws.onerror = () => {
      clearTimeout(timer);
      reject(new Error("connect failed"));
    };
  });
}

// ─── Connection ─────────────────────────────────────────────────────

describe("WebSocket Connection", () => {
  test("connects and receives sidecar.ready", async () => {
    const ws = await wsConnect();
    try {
      const ready = await ws.waitFor((m) => m.type === "sidecar.ready");
      expect(ready.type).toBe("sidecar.ready");
      expect(ready.port).toBe(WS_PORT);
      expect(ready.version).toBeDefined();
    } finally {
      ws.close();
    }
  });

  test("multiple clients can connect", async () => {
    const ws1 = await wsConnect();
    const ws2 = await wsConnect();
    try {
      const ready1 = await ws1.waitFor((m) => m.type === "sidecar.ready");
      const ready2 = await ws2.waitFor((m) => m.type === "sidecar.ready");
      expect(ready1.type).toBe("sidecar.ready");
      expect(ready2.type).toBe("sidecar.ready");
    } finally {
      ws1.close();
      ws2.close();
    }
  });
});

// ─── Command Dispatch ───────────────────────────────────────────────

describe("WebSocket Command Dispatch", () => {
  test("session.create dispatches to SessionManager", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const prevCount = sessionCreateCalls.length;
      ws.send({
        type: "session.create",
        conversationId: "ws-test-create",
        agentConfig: {
          name: "WsTestBot",
          systemPrompt: "test",
          allowedTools: [],
          mcpServers: [],
          model: "claude-sonnet-4-6",
          maxTurns: 1,
          workingDirectory: "/tmp",
          skills: [],
        },
      });

      await new Promise((r) => setTimeout(r, 200));
      expect(sessionCreateCalls.length).toBe(prevCount + 1);
      expect(sessionCreateCalls[sessionCreateCalls.length - 1].id).toBe("ws-test-create");
    } finally {
      ws.close();
    }
  });

  test("session.message dispatches to SessionManager", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const prevCount = sessionMessageCalls.length;
      ws.send({
        type: "session.message",
        sessionId: "ws-test-msg",
        text: "hello from ws test",
      });

      await new Promise((r) => setTimeout(r, 200));
      expect(sessionMessageCalls.length).toBe(prevCount + 1);
      expect(sessionMessageCalls[sessionMessageCalls.length - 1].text).toBe("hello from ws test");
    } finally {
      ws.close();
    }
  });

  test("agent.register populates agentDefinitions", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "agent.register",
        agents: [
          {
            name: "WsTestCoder",
            config: {
              name: "WsTestCoder",
              systemPrompt: "code things",
              allowedTools: [],
              mcpServers: [],
              model: "claude-sonnet-4-6",
              workingDirectory: "/tmp",
              skills: [],
            },
            instancePolicy: "spawn",
          },
        ],
      });

      await new Promise((r) => setTimeout(r, 200));
      expect(ctx.agentDefinitions.has("WsTestCoder")).toBe(true);
      expect(ctx.agentDefinitions.get("WsTestCoder")!.name).toBe("WsTestCoder");
    } finally {
      ws.close();
    }
  });
});

// ─── Broadcasting ───────────────────────────────────────────────────

describe("WebSocket Broadcasting", () => {
  test("broadcast sends event to all connected clients", async () => {
    const ws1 = await wsConnect();
    const ws2 = await wsConnect();
    try {
      await ws1.waitFor((m) => m.type === "sidecar.ready");
      await ws2.waitFor((m) => m.type === "sidecar.ready");

      const collect1 = ws1.collectNew(1, 2000);
      const collect2 = ws2.collectNew(1, 2000);

      const event: SidecarEvent = {
        type: "blackboard.update",
        key: "broadcast.test",
        value: "hello",
        writtenBy: "test",
      };
      wsServer.broadcast(event);

      const [msgs1, msgs2] = await Promise.all([collect1, collect2]);
      expect(msgs1).toHaveLength(1);
      expect(msgs1[0].type).toBe("blackboard.update");
      expect(msgs1[0].key).toBe("broadcast.test");
      expect(msgs2).toHaveLength(1);
      expect(msgs2[0].type).toBe("blackboard.update");
    } finally {
      ws1.close();
      ws2.close();
    }
  });
});
