/**
 * API tests for the WebSocket command/event protocol.
 *
 * Boots a real WsServer and tests connect, ready event, command dispatch,
 * and event broadcasting. Uses mock SessionManager to avoid real Claude SDK calls.
 *
 * Usage: ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) bun test test/api/ws-protocol.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { WsServer } from "../../src/ws-server.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";

const WS_PORT = 19849 + Math.floor(Math.random() * 1000);
let wsServer: WsServer;
let ctx: ToolContext;
let sessionCreateCalls: Array<{ id: string; config: any }>;
let sessionMessageCalls: Array<{ id: string; text: string }>;
let forkSessionCalls: Array<{ parent: string; child: string }>;
let sessionBulkResumeCalls: Array<{ sessions: any[] }>;
let sessionUpdateModeCalls: Array<{
  sessionId: string;
  interactive: boolean;
  instancePolicy?: string;
  instancePolicyPoolMax?: number;
}>;

const mockSessionManager = {
  createSession: async (id: string, config: any) => {
    sessionCreateCalls.push({ id, config });
  },
  sendMessage: async (id: string, text: string) => {
    sessionMessageCalls.push({ id, text });
  },
  resumeSession: async () => {},
  bulkResume: async (sessions: any[]) => {
    sessionBulkResumeCalls.push({ sessions });
  },
  updateSessionMode: (sessionId: string, interactive: boolean, instancePolicy?: string, instancePolicyPoolMax?: number) => {
    sessionUpdateModeCalls.push({ sessionId, interactive, instancePolicy, instancePolicyPoolMax });
  },
  forkSession: async (parent: string, child: string) => {
    forkSessionCalls.push({ parent, child });
  },
  pauseSession: async () => {},
} as any;

beforeAll(() => {
  sessionCreateCalls = [];
  sessionMessageCalls = [];
  forkSessionCalls = [];
  sessionBulkResumeCalls = [];
  sessionUpdateModeCalls = [];

  ctx = {
    blackboard: new BlackboardStore(`ws-test-${Date.now()}`),
    taskBoard: new TaskBoardStore(`ws-test-${Date.now()}`),
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
    broadcast: () => {},
    spawnSession: async (sid, config, prompt, wait) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
  };

  wsServer = new WsServer(WS_PORT, mockSessionManager, ctx);
});

afterAll(() => {
  wsServer.close();
});

import { wsConnectDirect } from "../helpers.js";

function wsConnect(timeoutMs = 5000) { return wsConnectDirect(WS_PORT, timeoutMs); }

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
  test.each([
    {
      provider: "claude",
      model: "claude-sonnet-4-6",
    },
    {
      provider: "claude",
      model: "ollama:qwen3-coder:latest",
    },
    {
      provider: "codex",
      model: "gpt-5-codex",
    },
  ])("session.create dispatches $provider provider config to SessionManager", async ({ provider, model }) => {
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
          provider,
          model,
          maxTurns: 1,
          workingDirectory: "/tmp",
          skills: [],
        },
      });

      await new Promise((r) => setTimeout(r, 200));
      expect(sessionCreateCalls.length).toBe(prevCount + 1);
      expect(sessionCreateCalls[sessionCreateCalls.length - 1].id).toBe("ws-test-create");
      expect(sessionCreateCalls[sessionCreateCalls.length - 1].config.provider).toBe(provider);
      expect(sessionCreateCalls[sessionCreateCalls.length - 1].config.model).toBe(model);
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

  test("session.fork dispatches parent and child session ids to SessionManager", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const prev = forkSessionCalls.length;
      ws.send({
        type: "session.fork",
        sessionId: "ws-fork-parent",
        childSessionId: "ws-fork-child",
      });

      await new Promise((r) => setTimeout(r, 200));
      expect(forkSessionCalls.length).toBe(prev + 1);
      expect(forkSessionCalls[forkSessionCalls.length - 1]).toEqual({
        parent: "ws-fork-parent",
        child: "ws-fork-child",
      });
    } finally {
      ws.close();
    }
  });

  test("session.updateMode dispatches runtime mode updates to SessionManager", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const prev = sessionUpdateModeCalls.length;
      ws.send({
        type: "session.updateMode",
        sessionId: "ws-mode-session",
        interactive: false,
        instancePolicy: "spawn",
      });

      await new Promise((r) => setTimeout(r, 200));
      expect(sessionUpdateModeCalls.length).toBe(prev + 1);
      expect(sessionUpdateModeCalls[prev]).toEqual({
        sessionId: "ws-mode-session",
        interactive: false,
        instancePolicy: "spawn",
        instancePolicyPoolMax: undefined,
      });
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
              systemPrompt: "base prompt only",
              allowedTools: [],
              mcpServers: [
                { name: "Octocode", command: "npx", args: ["-y", "octocode-mcp"] },
                { name: "AppXray", command: "npx", args: ["-y", "@wix/appxray-mcp-server"] },
              ],
              model: "claude-sonnet-4-6",
              workingDirectory: "/tmp",
              skills: [
                { name: "Plan", content: "Plan before editing." },
                { name: "Verify", content: "Verify after editing." },
              ],
            },
            instancePolicy: "spawn",
          },
        ],
      });

      await new Promise((r) => setTimeout(r, 200));
      expect(ctx.agentDefinitions.has("WsTestCoder")).toBe(true);
      const config = ctx.agentDefinitions.get("WsTestCoder")!;
      expect(config.name).toBe("WsTestCoder");
      expect(config.systemPrompt).toBe("base prompt only");
      expect(config.skills.map((skill) => skill.name)).toEqual(["Plan", "Verify"]);
      expect(config.mcpServers.map((mcp) => mcp.name)).toEqual(["Octocode", "AppXray"]);
    } finally {
      ws.close();
    }
  });

  test("agent.register parses singleton policy", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "agent.register",
        agents: [
          {
            name: "WsSingleton",
            config: {
              name: "WsSingleton",
              systemPrompt: "test",
              allowedTools: [],
              mcpServers: [],
              model: "claude-sonnet-4-6",
              workingDirectory: "/tmp",
              skills: [],
            },
            instancePolicy: "singleton",
          },
        ],
      });

      await new Promise((r) => setTimeout(r, 200));
      const config = ctx.agentDefinitions.get("WsSingleton");
      expect(config).toBeDefined();
      expect(config!.instancePolicy).toBe("singleton");
    } finally {
      ws.close();
    }
  });

  test("agent.register parses pool:N policy format", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "agent.register",
        agents: [
          {
            name: "WsPoolAgent",
            config: {
              name: "WsPoolAgent",
              systemPrompt: "test",
              allowedTools: [],
              mcpServers: [],
              model: "claude-sonnet-4-6",
              workingDirectory: "/tmp",
              skills: [],
            },
            instancePolicy: "pool:3",
          },
        ],
      });

      await new Promise((r) => setTimeout(r, 200));
      const config = ctx.agentDefinitions.get("WsPoolAgent");
      expect(config).toBeDefined();
      expect(config!.instancePolicy).toBe("pool");
      expect(config!.instancePolicyPoolMax).toBe(3);
    } finally {
      ws.close();
    }
  });

  test("delegate.task broadcasts peer.delegate event", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      // Register an agent definition first
      const delegateAgentName = `DelegateTarget-${Date.now()}`;
      ctx.agentDefinitions.set(delegateAgentName, {
        name: delegateAgentName,
        systemPrompt: "test delegate",
        allowedTools: [],
        mcpServers: [],
        model: "claude-sonnet-4-6",
        workingDirectory: "/tmp",
        skills: [],
        instancePolicy: "spawn",
      });

      // Create a source session so peer.delegate has a "from" name
      ctx.sessions.create("delegate-src", {
        name: "Orchestrator",
        systemPrompt: "test",
        allowedTools: [],
        mcpServers: [],
        model: "claude-sonnet-4-6",
        workingDirectory: "/tmp",
        skills: [],
      });

      ws.send({
        type: "delegate.task",
        sessionId: "delegate-src",
        toAgent: delegateAgentName,
        task: "implement login",
        context: "Use OAuth",
        waitForResult: false,
      });

      const event = await ws.waitFor(
        (m) => m.type === "peer.delegate" && m.to === delegateAgentName,
        3000,
      );
      expect(event.type).toBe("peer.delegate");
      expect(event.from).toBe("Orchestrator");
      expect(event.to).toBe(delegateAgentName);
      expect(event.task).toBe("implement login");
    } finally {
      ws.close();
    }
  });

  test("delegate.task errors for unknown agent", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "delegate.task",
        sessionId: "some-session",
        toAgent: "NonExistentAgent",
        task: "do something",
        waitForResult: false,
      });

      const event = await ws.waitFor((m) => m.type === "session.error", 3000);
      expect(event.type).toBe("session.error");
      expect(event.error).toContain("not found");
    } finally {
      ws.close();
    }
  });

  test("connector.completeAuth is listed without exposing credentials", async () => {
    const ws = await wsConnect();
    const connectionId = `connector-${Date.now()}`;
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "connector.completeAuth",
        connection: {
          id: connectionId,
          provider: "x",
          installScope: "system",
          displayName: "X Sandbox",
          grantedScopes: ["users.read"],
          authMode: "pkce-native",
          writePolicy: "require-approval",
          status: "connected",
        },
        credentials: {
          accessToken: "secret-token",
        },
      });

      const changed = await ws.waitFor(
        (m) => m.type === "connector.statusChanged" && m.connection.id === connectionId,
        3000,
      );
      expect(changed.type).toBe("connector.statusChanged");

      ws.send({ type: "connector.list" });
      const listed = await ws.waitFor((m) => m.type === "connector.list.result", 3000);
      expect(listed.type).toBe("connector.list.result");
      const stored = listed.connections.find((entry: any) => entry.id === connectionId);
      expect(stored).toBeDefined();
      expect(stored.accessToken).toBeUndefined();
      expect(stored.displayName).toBe("X Sandbox");
    } finally {
      ws.close();
    }
  });

  test("connector.test fails fast when runtime credentials are missing", async () => {
    const ws = await wsConnect();
    const connectionId = `connector-missing-${Date.now()}`;
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "connector.completeAuth",
        connection: {
          id: connectionId,
          provider: "slack",
          installScope: "system",
          displayName: "Slack Sandbox",
          grantedScopes: ["channels:read"],
          authMode: "brokered",
          writePolicy: "require-approval",
          status: "connected",
        },
      });
      await ws.waitFor((m) => m.type === "connector.statusChanged" && m.connection.id === connectionId, 3000);

      ws.send({ type: "connector.test", connectionId });
      const changed = await ws.waitFor(
        (m) => m.type === "connector.statusChanged" && m.connection.id === connectionId && m.connection.status === "failed",
        3000,
      );
      expect(changed.connection.statusMessage).toContain("No runtime credentials");

      const audit = await ws.waitFor(
        (m) => m.type === "connector.audit" && m.connectionId === connectionId && m.action === "connector.test",
        3000,
      );
      expect(audit.type).toBe("connector.audit");
      expect(audit.outcome).toBe("failed");
    } finally {
      ws.close();
    }
  });

  test("connector.revoke updates runtime state to revoked", async () => {
    const ws = await wsConnect();
    const connectionId = `connector-revoke-${Date.now()}`;
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "connector.completeAuth",
        connection: {
          id: connectionId,
          provider: "facebook",
          installScope: "system",
          displayName: "Facebook Sandbox",
          grantedScopes: ["public_profile"],
          authMode: "brokered",
          writePolicy: "read-only",
          status: "connected",
        },
        credentials: {
          accessToken: "secret-token",
        },
      });
      await ws.waitFor((m) => m.type === "connector.statusChanged" && m.connection.id === connectionId, 3000);

      ws.send({ type: "connector.revoke", connectionId });
      const changed = await ws.waitFor(
        (m) => m.type === "connector.statusChanged" && m.connection.id === connectionId && m.connection.status === "revoked",
        3000,
      );
      expect(changed.connection.statusMessage).toBe("Credentials removed.");
    } finally {
      ws.close();
    }
  });

  test("connector.test succeeds and enriches connector identity metadata", async () => {
    const ws = await wsConnect();
    const connectionId = `connector-success-${Date.now()}`;
    const originalFetch = globalThis.fetch;
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({
        data: {
          id: "user-1",
          username: "sandbox",
          name: "Sandbox User",
        },
      }), { status: 200 })) as typeof fetch;

    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "connector.completeAuth",
        connection: {
          id: connectionId,
          provider: "x",
          installScope: "system",
          displayName: "X Sandbox",
          grantedScopes: ["users.read"],
          authMode: "pkce-native",
          writePolicy: "require-approval",
          status: "connected",
        },
        credentials: {
          accessToken: "secret-token",
        },
      });
      await ws.waitFor((m) => m.type === "connector.statusChanged" && m.connection.id === connectionId, 3000);

      ws.send({ type: "connector.test", connectionId });
      const changed = await ws.waitFor(
        (m) =>
          m.type === "connector.statusChanged" &&
          m.connection.id === connectionId &&
          m.connection.accountId === "user-1",
        3000,
      );
      expect(changed.connection.status).toBe("connected");
      expect(changed.connection.accountHandle).toBe("@sandbox");

      const audit = await ws.waitFor(
        (m) =>
          m.type === "connector.audit" &&
          m.connectionId === connectionId &&
          m.action === "connector.test",
        3000,
      );
      expect(audit.type).toBe("connector.audit");
      expect(audit.outcome).toBe("passed");
    } finally {
      globalThis.fetch = originalFetch;
      ws.close();
    }
  });
});

// ─── Delegation Policy Routing ──────────────────────────────────────

describe("WebSocket Delegation Policy Routing", () => {
  test("delegate.task with singleton reuses existing session inbox", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const agentName = `WsSingletonRoute-${Date.now()}`;
      const existingSessionId = `existing-singleton-${Date.now()}`;

      ctx.agentDefinitions.set(agentName, {
        name: agentName,
        systemPrompt: "test",
        allowedTools: [],
        mcpServers: [],
        model: "claude-sonnet-4-6",
        workingDirectory: "/tmp",
        skills: [],
        instancePolicy: "singleton",
      } as any);

      ctx.sessions.create(existingSessionId, {
        name: agentName,
        systemPrompt: "test",
        allowedTools: [],
        mcpServers: [],
        model: "claude-sonnet-4-6",
        workingDirectory: "/tmp",
        skills: [],
      });

      const srcSid = `singleton-src-${Date.now()}`;
      ctx.sessions.create(srcSid, {
        name: "Orchestrator",
        systemPrompt: "test",
        allowedTools: [],
        mcpServers: [],
        model: "claude-sonnet-4-6",
        workingDirectory: "/tmp",
        skills: [],
      });

      ws.send({
        type: "delegate.task",
        sessionId: srcSid,
        toAgent: agentName,
        task: "reuse singleton",
        waitForResult: false,
      });

      const event = await ws.waitFor((m) => m.type === "peer.delegate" && m.to === agentName, 3000);
      expect(event).toBeDefined();

      await new Promise((r) => setTimeout(r, 300));
      const inbox = ctx.messages.peek(existingSessionId);
      expect(inbox).toBeGreaterThanOrEqual(1);
    } finally {
      ws.close();
    }
  });

  test("delegate.task with pool at capacity routes to least-busy inbox", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const agentName = `WsPoolRoute-${Date.now()}`;
      ctx.agentDefinitions.set(agentName, {
        name: agentName,
        systemPrompt: "test",
        allowedTools: [],
        mcpServers: [],
        model: "claude-sonnet-4-6",
        workingDirectory: "/tmp",
        skills: [],
        instancePolicy: "pool",
        instancePolicyPoolMax: 2,
      } as any);

      const sid1 = `pool-1-${Date.now()}`;
      const sid2 = `pool-2-${Date.now()}`;
      ctx.sessions.create(sid1, { name: agentName, systemPrompt: "t", allowedTools: [], mcpServers: [], model: "claude-sonnet-4-6", workingDirectory: "/tmp", skills: [] });
      ctx.sessions.create(sid2, { name: agentName, systemPrompt: "t", allowedTools: [], mcpServers: [], model: "claude-sonnet-4-6", workingDirectory: "/tmp", skills: [] });

      ctx.messages.push(sid1, {
        id: "busy-1", from: "x", fromAgent: "X", to: sid1,
        text: "busy", priority: "normal", timestamp: new Date().toISOString(), read: false,
      });
      ctx.messages.push(sid1, {
        id: "busy-2", from: "x", fromAgent: "X", to: sid1,
        text: "busier", priority: "normal", timestamp: new Date().toISOString(), read: false,
      });

      const srcSid = `pool-src-${Date.now()}`;
      ctx.sessions.create(srcSid, { name: "PoolOrch", systemPrompt: "t", allowedTools: [], mcpServers: [], model: "claude-sonnet-4-6", workingDirectory: "/tmp", skills: [] });

      ws.send({
        type: "delegate.task",
        sessionId: srcSid,
        toAgent: agentName,
        task: "pool task",
        waitForResult: false,
      });

      await ws.waitFor((m) => m.type === "peer.delegate" && m.to === agentName, 3000);
      await new Promise((r) => setTimeout(r, 300));

      const inbox2 = ctx.messages.peek(sid2);
      expect(inbox2).toBeGreaterThanOrEqual(1);
    } finally {
      ws.close();
    }
  });

  test("session.pause and session.resume dispatch to SessionManager", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `pause-resume-${Date.now()}`;

      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: {
          name: "PauseResumeBot",
          systemPrompt: "test",
          allowedTools: [],
          mcpServers: [],
          model: "claude-sonnet-4-6",
          maxTurns: 1,
          workingDirectory: "/tmp",
          skills: [],
        },
      });
      await new Promise((r) => setTimeout(r, 300));

      ws.send({ type: "session.pause", sessionId: sid });
      await new Promise((r) => setTimeout(r, 200));

      ws.send({ type: "session.resume", sessionId: sid, claudeSessionId: "fake-id" });
      await new Promise((r) => setTimeout(r, 200));
      // Mock SessionManager accepted both commands without error (no session.error broadcast)
      const errors = ws.buffer.filter((m) => m.type === "session.error" && m.sessionId === sid);
      expect(errors).toHaveLength(0);
    } finally {
      ws.close();
    }
  });

  test("session.bulkResume dispatches the exact mixed-provider recovery payload to SessionManager", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const prevCount = sessionBulkResumeCalls.length;

      ws.send({
        type: "session.bulkResume",
        sessions: [
          {
            sessionId: "recover-a",
            claudeSessionId: "claude-a",
            agentConfig: {
              name: "RecoverA",
              systemPrompt: "test",
              allowedTools: [],
              mcpServers: [],
              provider: "claude",
              model: "claude-sonnet-4-6",
              maxTurns: 2,
              workingDirectory: "/tmp/recover-a",
              skills: [],
            },
          },
          {
            sessionId: "recover-b",
            claudeSessionId: "claude-b",
            agentConfig: {
              name: "RecoverB",
              systemPrompt: "test",
              allowedTools: [],
              mcpServers: [],
              provider: "codex",
              model: "gpt-5-codex",
              maxTurns: 3,
              workingDirectory: "/tmp/recover-b",
              skills: [],
            },
          },
        ],
      });

      await new Promise((r) => setTimeout(r, 200));
      expect(sessionBulkResumeCalls.length).toBe(prevCount + 1);
      expect(sessionBulkResumeCalls[prevCount].sessions).toEqual([
        {
          sessionId: "recover-a",
          claudeSessionId: "claude-a",
          agentConfig: {
            name: "RecoverA",
            systemPrompt: "test",
            allowedTools: [],
            mcpServers: [],
            provider: "claude",
            model: "claude-sonnet-4-6",
            maxTurns: 2,
            workingDirectory: "/tmp/recover-a",
            skills: [],
          },
        },
        {
          sessionId: "recover-b",
          claudeSessionId: "claude-b",
          agentConfig: {
            name: "RecoverB",
            systemPrompt: "test",
            allowedTools: [],
            mcpServers: [],
            provider: "codex",
            model: "gpt-5-codex",
            maxTurns: 3,
            workingDirectory: "/tmp/recover-b",
            skills: [],
          },
        },
      ]);
    } finally {
      ws.close();
    }
  });

  test("session.bulkResume does not disrupt multi-client broadcasting", async () => {
    const ws1 = await wsConnect();
    const ws2 = await wsConnect();
    try {
      await ws1.waitFor((m) => m.type === "sidecar.ready");
      await ws2.waitFor((m) => m.type === "sidecar.ready");

      ws1.send({
        type: "session.bulkResume",
        sessions: [
          {
            sessionId: "broadcast-recover",
            claudeSessionId: "claude-broadcast",
            agentConfig: {
              name: "BroadcastRecover",
              systemPrompt: "test",
              allowedTools: [],
              mcpServers: [],
              model: "claude-sonnet-4-6",
              workingDirectory: "/tmp/broadcast-recover",
              skills: [],
            },
          },
        ],
      });

      await new Promise((r) => setTimeout(r, 200));
      const errors1 = ws1.buffer.filter((m) => m.type === "session.error");
      const errors2 = ws2.buffer.filter((m) => m.type === "session.error");
      expect(errors1).toHaveLength(0);
      expect(errors2).toHaveLength(0);

      const collect1 = ws1.collectNew(1, 2000);
      const collect2 = ws2.collectNew(1, 2000);
      wsServer.broadcast({
        type: "blackboard.update",
        key: "recovery.broadcast",
        value: "ok",
        writtenBy: "test",
      });

      const [msgs1, msgs2] = await Promise.all([collect1, collect2]);
      expect(msgs1).toHaveLength(1);
      expect(msgs2).toHaveLength(1);
      expect(msgs1[0].type).toBe("blackboard.update");
      expect(msgs2[0].type).toBe("blackboard.update");
    } finally {
      ws1.close();
      ws2.close();
    }
  });

  test("session.create with full config including skills and maxBudget", async () => {
    const ws = await wsConnect();
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const prevCount = sessionCreateCalls.length;

      ws.send({
        type: "session.create",
        conversationId: `full-config-${Date.now()}`,
        agentConfig: {
          name: "FullConfigBot",
          systemPrompt: "test with skills",
          allowedTools: ["Read", "Write", "Shell"],
          mcpServers: [{ name: "TestMCP", command: "echo", args: ["hi"] }],
          model: "claude-sonnet-4-6",
          maxTurns: 20,
          maxBudget: 5.0,
          workingDirectory: "/tmp",
          skills: [{ name: "test-skill", content: "# Test Skill\nDo something special." }],
        },
      });

      await new Promise((r) => setTimeout(r, 300));
      expect(sessionCreateCalls.length).toBe(prevCount + 1);
      const call = sessionCreateCalls[sessionCreateCalls.length - 1];
      expect(call.config.name).toBe("FullConfigBot");
      expect(call.config.maxBudget).toBe(5.0);
      expect(call.config.skills).toHaveLength(1);
      expect(call.config.allowedTools).toHaveLength(3);
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
