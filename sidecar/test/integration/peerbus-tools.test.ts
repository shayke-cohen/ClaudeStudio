/**
 * Integration tests for PeerBus SDK tools.
 *
 * Tests the tool factory functions (createBlackboardTools, createMessagingTools,
 * createChatTools, createWorkspaceTools) by wiring them through a real ToolContext
 * with real stores — but no sidecar, no WebSocket, no Claude SDK.
 *
 * Usage: CLAUDESTUDIO_DATA_DIR=/tmp/claudestudio-test-$(date +%s) bun test test/integration/peerbus-tools.test.ts
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";
import { createBlackboardTools } from "../../src/tools/blackboard-tools.js";
import { createMessagingTools } from "../../src/tools/messaging-tools.js";
import { createChatTools } from "../../src/tools/chat-tools.js";
import { createWorkspaceTools } from "../../src/tools/workspace-tools.js";

const agentConfig: AgentConfig = {
  name: "TestAgent",
  systemPrompt: "test",
  allowedTools: [],
  mcpServers: [],
  model: "claude-sonnet-4-6",
  workingDirectory: "/tmp",
  skills: [],
};

function createTestContext(): {
  ctx: ToolContext;
  events: SidecarEvent[];
  spawnCalls: Array<{ sessionId: string; config: AgentConfig; prompt: string; wait: boolean }>;
} {
  const events: SidecarEvent[] = [];
  const spawnCalls: Array<{ sessionId: string; config: AgentConfig; prompt: string; wait: boolean }> = [];

  const ctx: ToolContext = {
    blackboard: new BlackboardStore(`test-${Date.now()}-${Math.random()}`),
    taskBoard: new TaskBoardStore(`test-${Date.now()}-${Math.random()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast: (event) => events.push(event),
    spawnSession: async (sessionId, config, prompt, wait) => {
      spawnCalls.push({ sessionId, config, prompt, wait });
      return { sessionId, result: wait ? "mock-result" : undefined };
    },
    agentDefinitions: new Map(),
  };

  return { ctx, events, spawnCalls };
}

function parseToolResult(result: any): any {
  return JSON.parse(result.content[0].text);
}

/** Invoke an SDK tool's handler directly, bypassing the SDK runtime. */
async function call(toolObj: any, args: Record<string, any>, extra: Record<string, any> = {}): Promise<any> {
  if (typeof toolObj.execute === "function") {
    return toolObj.execute(args, extra);
  }
  if (typeof toolObj.handler === "function") {
    return toolObj.handler(args, extra);
  }
  throw new TypeError("Tool object does not expose execute() or handler()");
}

function findTool(tools: any[], name: string) {
  const t = tools.find((t: any) => t.name === name);
  if (!t) throw new Error(`Tool "${name}" not found in [${tools.map((t: any) => t.name)}]`);
  return t;
}

// ─── Blackboard Tools ───────────────────────────────────────────────

describe("Blackboard Tools (integration)", () => {
  let ctx: ToolContext;
  let events: SidecarEvent[];
  let tools: ReturnType<typeof createBlackboardTools>;

  beforeEach(() => {
    const testCtx = createTestContext();
    ctx = testCtx.ctx;
    events = testCtx.events;
    tools = createBlackboardTools(ctx);
  });

  test("blackboard_write writes and broadcasts event", async () => {
    const result = await call(findTool(tools, "blackboard_write"), { key: "test.key", value: '{"hello":"world"}' });
    const parsed = parseToolResult(result);

    expect(parsed.success).toBe(true);
    expect(parsed.key).toBe("test.key");

    expect(events).toHaveLength(1);
    expect(events[0].type).toBe("blackboard.update");
    if (events[0].type === "blackboard.update") {
      expect(events[0].key).toBe("test.key");
    }
  });

  test("blackboard_read returns entry", async () => {
    ctx.blackboard.write("rk", "rv", "writer");
    const result = await call(findTool(tools, "blackboard_read"), { key: "rk" });
    const parsed = parseToolResult(result);

    expect(parsed.key).toBe("rk");
    expect(parsed.value).toBe("rv");
  });

  test("blackboard_read returns error for missing key", async () => {
    const result = await call(findTool(tools, "blackboard_read"), { key: "nope" });
    expect(parseToolResult(result).error).toBe("not_found");
  });

  test("blackboard_query returns matching entries", async () => {
    ctx.blackboard.write("q.a", "1", "w");
    ctx.blackboard.write("q.b", "2", "w");
    ctx.blackboard.write("other", "3", "w");

    const result = await call(findTool(tools, "blackboard_query"), { pattern: "q.*" });
    expect(parseToolResult(result)).toHaveLength(2);
  });

  test("blackboard_subscribe returns current matches", async () => {
    ctx.blackboard.write("sub.a", "1", "w");
    const result = await call(findTool(tools, "blackboard_subscribe"), { pattern: "sub.*" });
    const parsed = parseToolResult(result);

    expect(parsed.subscribed).toBe("sub.*");
    expect(parsed.currentEntries).toHaveLength(1);
  });
});

// ─── Messaging Tools ────────────────────────────────────────────────

describe("Messaging Tools (integration)", () => {
  let ctx: ToolContext;
  let events: SidecarEvent[];
  let spawnCalls: Array<any>;

  beforeEach(() => {
    const testCtx = createTestContext();
    ctx = testCtx.ctx;
    events = testCtx.events;
    spawnCalls = testCtx.spawnCalls;

    ctx.sessions.create("session-a", { ...agentConfig, name: "AgentA" });
    ctx.sessions.create("session-b", { ...agentConfig, name: "AgentB" });
  });

  test("peer_send_message delivers to target inbox", async () => {
    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_send_message"), { to_agent: "session-b", message: "ping" });
    const parsed = parseToolResult(result);
    expect(parsed.sent).toBe(true);

    const inbox = ctx.messages.drain("session-b");
    expect(inbox).toHaveLength(1);
    expect(inbox[0].text).toBe("ping");
    expect(inbox[0].fromAgent).toBe("AgentA");

    expect(events.some((e) => e.type === "peer.chat")).toBe(true);
  });

  test("peer_send_message resolves agent by name", async () => {
    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_send_message"), { to_agent: "AgentB", message: "by name" });
    expect(parseToolResult(result).sent).toBe(true);
    expect(ctx.messages.peek("session-b")).toBe(1);
  });

  test("peer_send_message returns error for unknown agent", async () => {
    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_send_message"), { to_agent: "ghost", message: "?" });
    expect(parseToolResult(result).error).toBe("agent_not_found");
  });

  test("peer_broadcast sends to all except sender", async () => {
    ctx.sessions.create("session-c", { ...agentConfig, name: "AgentC" });
    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_broadcast"), { channel: "status", message: "starting" });
    const parsed = parseToolResult(result);

    expect(parsed.broadcast).toBe(true);
    expect(parsed.recipients).toBe(2);
    expect(ctx.messages.peek("session-a")).toBe(0);
    expect(ctx.messages.peek("session-b")).toBe(1);
    expect(ctx.messages.peek("session-c")).toBe(1);
  });

  test("peer_receive_messages drains inbox", async () => {
    ctx.messages.push("session-a", {
      id: "m1",
      from: "session-b",
      fromAgent: "AgentB",
      to: "session-a",
      text: "hey",
      priority: "normal",
      timestamp: new Date().toISOString(),
      read: false,
    });

    const tools = createMessagingTools(ctx, "session-a");
    const recvTool = findTool(tools, "peer_receive_messages");

    const result = await call(recvTool, {});
    const parsed = parseToolResult(result);
    expect(parsed.count).toBe(1);
    expect(parsed.messages[0].text).toBe("hey");

    const again = await call(recvTool, {});
    expect(parseToolResult(again).count).toBe(0);
  });

  test("peer_list_agents returns sessions and definitions", async () => {
    ctx.agentDefinitions.set("Coder", agentConfig);
    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_list_agents"), {});
    const parsed = parseToolResult(result);

    expect(parsed.activeSessions.length).toBeGreaterThanOrEqual(2);
    const self = parsed.activeSessions.find((a: any) => a.sessionId === "session-a");
    expect(self.isSelf).toBe(true);
    expect(parsed.registeredAgents).toHaveLength(1);
    expect(parsed.registeredAgents[0].name).toBe("Coder");
  });

  test("peer_delegate_task spawns session via agentDefinitions", async () => {
    ctx.agentDefinitions.set("Coder", {
      ...agentConfig,
      name: "Coder",
      mcpServers: [
        { name: "Octocode", command: "npx", args: ["-y", "octocode-mcp"] },
        { name: "AppXray", command: "npx", args: ["-y", "@wix/appxray-mcp-server"] },
      ],
      skills: [
        { name: "Plan", content: "Plan before editing." },
        { name: "Verify", content: "Verify after editing." },
      ],
    });
    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_delegate_task"), {
      to_agent: "Coder",
      task: "implement sorting",
      wait_for_result: true,
    });
    const parsed = parseToolResult(result);

    expect(parsed.delegated).toBe(true);
    expect(parsed.waitedForResult).toBe(true);
    expect(parsed.result).toBe("mock-result");
    expect(spawnCalls).toHaveLength(1);
    expect(spawnCalls[0].prompt).toBe("implement sorting");
    expect(spawnCalls[0].config.skills.map((skill: any) => skill.name)).toEqual(["Plan", "Verify"]);
    expect(spawnCalls[0].config.mcpServers.map((mcp: any) => mcp.name)).toEqual(["Octocode", "AppXray"]);
    expect(events.some((e) => e.type === "peer.delegate")).toBe(true);
  });

  test("peer_delegate_task falls back to inbox for existing sessions", async () => {
    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_delegate_task"), {
      to_agent: "AgentB",
      task: "review code",
    });
    const parsed = parseToolResult(result);

    expect(parsed.delegated).toBe(true);
    expect(parsed.method).toBe("inbox");
    expect(ctx.messages.peek("session-b")).toBe(1);
  });

  test("peer_delegate_task returns error for unknown agent", async () => {
    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_delegate_task"), { to_agent: "Ghost", task: "nothing" });
    expect(parseToolResult(result).error).toBe("agent_not_found");
  });

  test("peer_delegate_task with singleton policy reuses existing session", async () => {
    const singletonConfig = { ...agentConfig, name: "DevOps", instancePolicy: "singleton" as const };
    ctx.agentDefinitions.set("DevOps", singletonConfig);
    ctx.sessions.create("devops-1", singletonConfig);

    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_delegate_task"), {
      to_agent: "DevOps",
      task: "setup CI",
    });
    const parsed = parseToolResult(result);

    expect(parsed.delegated).toBe(true);
    expect(parsed.method).toBe("reused_singleton");
    expect(parsed.sessionId).toBe("devops-1");
    expect(spawnCalls).toHaveLength(0);
    expect(ctx.messages.peek("devops-1")).toBe(1);
  });

  test("peer_delegate_task with singleton spawns when no active session", async () => {
    const singletonConfig = { ...agentConfig, name: "DevOps", instancePolicy: "singleton" as const };
    ctx.agentDefinitions.set("DevOps", singletonConfig);

    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_delegate_task"), {
      to_agent: "DevOps",
      task: "deploy",
      wait_for_result: true,
    });
    const parsed = parseToolResult(result);

    expect(parsed.delegated).toBe(true);
    expect(parsed.method).toBe("spawned");
    expect(spawnCalls).toHaveLength(1);
    expect(spawnCalls[0].config.name).toBe("DevOps");
  });

  test("peer_delegate_task with pool spawns when under cap", async () => {
    const poolConfig = { ...agentConfig, name: "Tester", instancePolicy: "pool" as const, instancePolicyPoolMax: 2 };
    ctx.agentDefinitions.set("Tester", poolConfig);
    ctx.sessions.create("tester-1", poolConfig);

    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_delegate_task"), {
      to_agent: "Tester",
      task: "test login",
      wait_for_result: false,
    });
    const parsed = parseToolResult(result);

    expect(parsed.delegated).toBe(true);
    expect(parsed.method).toBe("spawned");
    expect(spawnCalls).toHaveLength(1);
  });

  test("peer_delegate_task with pool routes to inbox when at cap", async () => {
    const poolConfig = { ...agentConfig, name: "Tester", instancePolicy: "pool" as const, instancePolicyPoolMax: 2 };
    ctx.agentDefinitions.set("Tester", poolConfig);
    ctx.sessions.create("tester-1", poolConfig);
    ctx.sessions.create("tester-2", poolConfig);

    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_delegate_task"), {
      to_agent: "Tester",
      task: "test checkout",
    });
    const parsed = parseToolResult(result);

    expect(parsed.delegated).toBe(true);
    expect(parsed.method).toBe("pool_routed");
    expect(spawnCalls).toHaveLength(0);
    const totalInbox = ctx.messages.peek("tester-1") + ctx.messages.peek("tester-2");
    expect(totalInbox).toBe(1);
  });

  test("peer_delegate_task pool routes to least-busy session", async () => {
    const poolConfig = { ...agentConfig, name: "Tester", instancePolicy: "pool" as const, instancePolicyPoolMax: 2 };
    ctx.agentDefinitions.set("Tester", poolConfig);
    ctx.sessions.create("tester-1", poolConfig);
    ctx.sessions.create("tester-2", poolConfig);

    // Give tester-1 some messages to make it busier
    ctx.messages.push("tester-1", {
      id: "existing-1", from: "x", fromAgent: "X", to: "tester-1",
      text: "busy", priority: "normal", timestamp: new Date().toISOString(), read: false,
    });
    ctx.messages.push("tester-1", {
      id: "existing-2", from: "x", fromAgent: "X", to: "tester-1",
      text: "busier", priority: "normal", timestamp: new Date().toISOString(), read: false,
    });

    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_delegate_task"), {
      to_agent: "Tester",
      task: "test signup",
    });
    const parsed = parseToolResult(result);

    expect(parsed.delegated).toBe(true);
    expect(parsed.method).toBe("pool_routed");
    expect(parsed.sessionId).toBe("tester-2");
  });

  test("peer_delegate_task includes context in prompt", async () => {
    ctx.agentDefinitions.set("Coder", { ...agentConfig, name: "Coder" });
    const tools = createMessagingTools(ctx, "session-a");
    await call(findTool(tools, "peer_delegate_task"), {
      to_agent: "Coder",
      task: "implement sorting",
      context: "Use mergesort. See blackboard research.sorting",
      wait_for_result: true,
    });

    expect(spawnCalls).toHaveLength(1);
    expect(spawnCalls[0].prompt).toContain("implement sorting");
    expect(spawnCalls[0].prompt).toContain("## Context");
    expect(spawnCalls[0].prompt).toContain("Use mergesort");
  });

  test("peer_delegate_task spawn policy creates unique session IDs each call", async () => {
    ctx.agentDefinitions.set("Worker", { ...agentConfig, name: "Worker", instancePolicy: "spawn" as const });
    const tools = createMessagingTools(ctx, "session-a");

    await call(findTool(tools, "peer_delegate_task"), {
      to_agent: "Worker",
      task: "task-1",
      wait_for_result: false,
    });
    await call(findTool(tools, "peer_delegate_task"), {
      to_agent: "Worker",
      task: "task-2",
      wait_for_result: false,
    });

    expect(spawnCalls).toHaveLength(2);
    expect(spawnCalls[0].sessionId).not.toBe(spawnCalls[1].sessionId);
  });

  test("peer_list_agents returns registered definitions separately from sessions", async () => {
    ctx.agentDefinitions.set("RegisteredCoder", { ...agentConfig, name: "RegisteredCoder" });
    ctx.agentDefinitions.set("RegisteredReviewer", { ...agentConfig, name: "RegisteredReviewer" });
    const tools = createMessagingTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_list_agents"), {});
    const parsed = parseToolResult(result);

    const regNames = parsed.registeredAgents.map((a: any) => a.name);
    expect(regNames).toContain("RegisteredCoder");
    expect(regNames).toContain("RegisteredReviewer");

    const sessionNames = parsed.activeSessions.map((a: any) => a.name);
    expect(sessionNames).toContain("AgentA");
    expect(sessionNames).toContain("AgentB");
    expect(sessionNames).not.toContain("RegisteredCoder");
  });
});

// ─── Chat Tools ─────────────────────────────────────────────────────

describe("Chat Tools (integration)", () => {
  let ctx: ToolContext;
  let events: SidecarEvent[];

  beforeEach(() => {
    const testCtx = createTestContext();
    ctx = testCtx.ctx;
    events = testCtx.events;

    ctx.sessions.create("session-a", { ...agentConfig, name: "AgentA" });
    ctx.sessions.create("session-b", { ...agentConfig, name: "AgentB" });
  });

  test("peer_chat_start creates channel, blocks, resolves on reply", async () => {
    const toolsA = createChatTools(ctx, "session-a");
    const startPromise = call(findTool(toolsA, "peer_chat_start"), {
      to_agent: "session-b",
      message: "discuss design",
      topic: "architecture",
    });

    await new Promise((r) => setTimeout(r, 50));
    const channels = ctx.channels.listOpen();
    expect(channels).toHaveLength(1);
    ctx.channels.addMessage(channels[0].id, "session-b", "AgentB", "I agree");

    const result = await startPromise;
    const parsed = parseToolResult(result);
    expect(parsed.reply).toBe("I agree");
    expect(parsed.from_agent).toBe("AgentB");
    expect(parsed.channel_id).toBeTruthy();
    expect(events.some((e) => e.type === "peer.chat")).toBe(true);
  });

  test("peer_chat_start returns error for unknown agent", async () => {
    const tools = createChatTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_chat_start"), { to_agent: "ghost", message: "hi" });
    expect(parseToolResult(result).error).toBe("agent_not_found");
  });

  test("peer_chat_reply sends and waits for response", async () => {
    const ch = ctx.channels.create("session-a", "AgentA", "session-b", "initial");
    const toolsB = createChatTools(ctx, "session-b");
    const replyPromise = call(findTool(toolsB, "peer_chat_reply"), {
      channel_id: ch.id,
      message: "B's reply",
    });

    await new Promise((r) => setTimeout(r, 50));
    ctx.channels.addMessage(ch.id, "session-a", "AgentA", "A's follow-up");

    const parsed = parseToolResult(await replyPromise);
    expect(parsed.reply).toBe("A's follow-up");
  });

  test("peer_chat_reply returns error for missing channel", async () => {
    const tools = createChatTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_chat_reply"), { channel_id: "bad-id", message: "?" });
    expect(parseToolResult(result).error).toBe("channel_not_found");
  });

  test("peer_chat_close ends channel and resolves waiters", async () => {
    const ch = ctx.channels.create("session-a", "AgentA", "session-b", "hi");
    const waiter = ctx.channels.waitForReply(ch.id, "session-b", 5000);

    const toolsA = createChatTools(ctx, "session-a");
    const result = await call(findTool(toolsA, "peer_chat_close"), {
      channel_id: ch.id,
      summary: "resolved the issue",
    });
    expect(parseToolResult(result).closed).toBe(true);

    const waiterResult = await waiter;
    expect("closed" in waiterResult).toBe(true);
  });

  test("peer_chat_listen finds incoming channel", async () => {
    ctx.channels.create("session-a", "AgentA", "session-b", "question?");
    const toolsB = createChatTools(ctx, "session-b");
    const result = await call(findTool(toolsB, "peer_chat_listen"), { timeout_ms: 1000 });
    const parsed = parseToolResult(result);

    expect(parsed.channel_id).toBeTruthy();
    expect(parsed.from_agent).toBe("AgentA");
    expect(parsed.message).toBe("question?");
  });

  test("peer_chat_listen returns timeout when no channels", async () => {
    const tools = createChatTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_chat_listen"), { timeout_ms: 100 });
    expect(parseToolResult(result).timeout).toBe(true);
  });

  test("peer_chat_invite adds participant and notifies", async () => {
    const ch = ctx.channels.create("session-a", "AgentA", "session-b", "let's add C");
    ctx.sessions.create("session-c", { ...agentConfig, name: "AgentC" });

    const toolsA = createChatTools(ctx, "session-a");
    const result = await call(findTool(toolsA, "peer_chat_invite"), {
      channel_id: ch.id,
      agent: "AgentC",
      context: "join our discussion",
    });
    expect(parseToolResult(result).invited).toBe(true);
    expect(ctx.channels.get(ch.id)!.participants).toContain("session-c");
    expect(ctx.messages.peek("session-c")).toBe(1);
  });

  test("peer_chat_invite returns error for unknown agent", async () => {
    const ch = ctx.channels.create("session-a", "AgentA", "session-b", "hi");
    const tools = createChatTools(ctx, "session-a");
    const result = await call(findTool(tools, "peer_chat_invite"), { channel_id: ch.id, agent: "ghost" });
    expect(parseToolResult(result).error).toBe("agent_not_found");
  });

  test("peer_chat_listen succeeds when message arrives before timeout", async () => {
    const toolsB = createChatTools(ctx, "session-b");
    const listenPromise = call(findTool(toolsB, "peer_chat_listen"), { timeout_ms: 3000 });

    await new Promise((r) => setTimeout(r, 50));
    ctx.channels.create("session-a", "AgentA", "session-b", "delayed question");

    const parsed = parseToolResult(await listenPromise);
    expect(parsed.channel_id).toBeTruthy();
    expect(parsed.from_agent).toBe("AgentA");
    expect(parsed.message).toBe("delayed question");
  });

  test("peer_chat_listen times out gracefully with no incoming", async () => {
    ctx.sessions.create("session-lonely", { ...agentConfig, name: "LonelyAgent" });
    const tools = createChatTools(ctx, "session-lonely");
    const result = await call(findTool(tools, "peer_chat_listen"), { timeout_ms: 100 });
    const parsed = parseToolResult(result);
    expect(parsed.timeout).toBe(true);
  });
});

// ─── Workspace Tools ────────────────────────────────────────────────

describe("Workspace Tools (integration)", () => {
  let ctx: ToolContext;

  beforeEach(() => {
    const testCtx = createTestContext();
    ctx = testCtx.ctx;
    ctx.sessions.create("session-a", { ...agentConfig, name: "AgentA" });
  });

  test("workspace_create returns id and path", async () => {
    const tools = createWorkspaceTools(ctx, "session-a");
    const result = await call(findTool(tools, "workspace_create"), { name: "collab-space" });
    const parsed = parseToolResult(result);

    expect(parsed.workspace_id).toBeTruthy();
    expect(parsed.name).toBe("collab-space");
    expect(parsed.path).toContain(parsed.workspace_id);
  });

  test("workspace_join adds participant", async () => {
    const ws = ctx.workspaces.create("test-ws", "session-a");
    ctx.sessions.create("session-b", { ...agentConfig, name: "AgentB" });

    const toolsB = createWorkspaceTools(ctx, "session-b");
    const result = await call(findTool(toolsB, "workspace_join"), { workspace_id: ws.id });
    const parsed = parseToolResult(result);

    expect(parsed.workspace_id).toBe(ws.id);
    expect(parsed.participants).toBe(2);
  });

  test("workspace_join returns error for missing workspace", async () => {
    const tools = createWorkspaceTools(ctx, "session-a");
    const result = await call(findTool(tools, "workspace_join"), { workspace_id: "bad-id" });
    expect(parseToolResult(result).error).toBe("workspace_not_found");
  });

  test("workspace_list returns all workspaces", async () => {
    ctx.workspaces.create("ws-1", "session-a");
    ctx.workspaces.create("ws-2", "session-a");

    const tools = createWorkspaceTools(ctx, "session-a");
    const result = await call(findTool(tools, "workspace_list"), {});
    const parsed = parseToolResult(result);

    expect(parsed.workspaces).toHaveLength(2);
    expect(parsed.workspaces[0].name).toBeDefined();
    expect(parsed.workspaces[0].workspace_id).toBeDefined();
  });
});
