/**
 * Integration tests for the complete delegation flow.
 *
 * Tests multiple components working together:
 *   - DelegationStore (real instance)
 *   - ask-user-tool (real createAskUserTool / helper exports)
 *   - ask-agent-tool (real createAskAgentTool)
 *   - Mock spawnSession (no actual Claude API calls)
 *
 * Covers:
 *   Group 1 — ask_user timeout → agent routing flow (via helper exports)
 *   Group 2 — ask_agent end-to-end with real DelegationStore
 *   Group 3 — session teardown cleans delegation config
 *
 * Usage: bun test test/integration/delegation-flow.test.ts
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { DelegationStore } from "../../src/stores/delegation-store.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import {
  createAskUserTool,
  leastBusyAgent,
  resolveTimeout,
  DEFAULT_TIMEOUT_MS,
  pendingQuestions,
  questionsBySession,
} from "../../src/tools/ask-user-tool.js";
import { createAskAgentTool } from "../../src/tools/ask-agent-tool.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";

// ─── Shared fixtures ──────────────────────────────────────────────────────────

const BASE_CONFIG: AgentConfig = {
  name: "TestAgent",
  systemPrompt: "You are a helpful assistant.",
  allowedTools: [],
  mcpServers: [],
  model: "claude-sonnet-4-6",
  workingDirectory: "/tmp",
  skills: [],
};

interface BuildCtxOptions {
  delegation?: DelegationStore;
  sessions?: SessionRegistry;
  messages?: MessageStore;
  agentDefinitions?: Map<string, AgentConfig>;
  spawnSession?: ToolContext["spawnSession"];
  broadcast?: (e: SidecarEvent) => void;
}

function buildCtx(
  events: SidecarEvent[],
  opts: BuildCtxOptions = {},
): ToolContext {
  return {
    delegation: opts.delegation ?? new DelegationStore(),
    sessions: opts.sessions ?? new SessionRegistry(),
    messages: opts.messages ?? new MessageStore(),
    agentDefinitions: opts.agentDefinitions ?? new Map(),
    broadcast: opts.broadcast ?? ((e) => events.push(e)),
    spawnSession:
      opts.spawnSession ??
      (async (sid) => ({ sessionId: sid, result: "mock answer" })),
    blackboard: new BlackboardStore(`test-${Date.now()}-${Math.random()}`),
    taskBoard: new TaskBoardStore(`test-${Date.now()}-${Math.random()}`),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    relayClient: { isConnected: () => false, connect: async () => {}, sendCommand: async () => ({}) } as any,
    conversationStore: {} as any,
    projectStore: {} as any,
    nostrTransport: {} as any,
  };
}

function parseResult(result: { content: Array<{ type: string; text: string }> }) {
  return JSON.parse(result.content[0].text);
}

async function callAskAgent(
  ctx: ToolContext,
  callingSessionId: string,
  args: { question: string; to_agent: string },
) {
  const tools = createAskAgentTool(ctx, callingSessionId);
  return tools[0].execute(args);
}

// ─── Group 1: ask_user timeout → agent routing flow ───────────────────────────

describe("ask_user — timeout triggers agent routing", () => {
  beforeEach(() => {
    // Clean up global pending question maps between tests
    pendingQuestions.clear();
    questionsBySession.clear();
  });

  test("resolveTimeout caps hint at the mode default", () => {
    // hint larger than mode default → capped to mode default
    expect(resolveTimeout(DEFAULT_TIMEOUT_MS.by_agents, 999)).toBe(DEFAULT_TIMEOUT_MS.by_agents);
    // hint smaller than mode default → hint wins
    expect(resolveTimeout(DEFAULT_TIMEOUT_MS.by_agents, 1)).toBe(1000);
    // no hint → mode default
    expect(resolveTimeout(DEFAULT_TIMEOUT_MS.off)).toBe(DEFAULT_TIMEOUT_MS.off);
  });

  test("leastBusyAgent returns the active session with fewest messages, excluding caller", () => {
    const sessions = new SessionRegistry();
    const messages = new MessageStore();

    sessions.create("s1", { ...BASE_CONFIG, name: "AgentA" });
    sessions.create("s2", { ...BASE_CONFIG, name: "AgentB" });
    sessions.create("s3", { ...BASE_CONFIG, name: "AgentC" });

    // Push 2 unread messages to s1, 1 to s2, 0 to s3
    const baseMsg = { from: "other", fromAgent: "Other", to: "", text: "hi", priority: "normal" as const, timestamp: new Date().toISOString(), read: false };
    messages.push("s1", { ...baseMsg, id: "m1", to: "s1" });
    messages.push("s1", { ...baseMsg, id: "m2", to: "s1" });
    messages.push("s2", { ...baseMsg, id: "m3", to: "s2" });

    const events: SidecarEvent[] = [];
    const ctx = buildCtx(events, { sessions, messages });

    // Caller is s1, so s1 is excluded — s3 (0 messages) should win
    const result = leastBusyAgent(ctx, "s1");
    expect(result).toBe("s3");
  });

  test("leastBusyAgent returns undefined when no other active sessions exist", () => {
    const sessions = new SessionRegistry();
    sessions.create("only", { ...BASE_CONFIG, name: "Solo" });
    const ctx = buildCtx([], { sessions });
    expect(leastBusyAgent(ctx, "only")).toBeUndefined();
  });

  test("ask_user in specific_agent mode broadcasts routing + resolved after timeout with isFallback:true", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "specific_agent", targetAgentName: "FallbackAgent" });

    const definitions = new Map<string, AgentConfig>([
      ["FallbackAgent", { ...BASE_CONFIG, name: "FallbackAgent" }],
    ]);

    const spawnSession: ToolContext["spawnSession"] = async (sid) => ({
      sessionId: sid,
      result: "FallbackAgent auto-answer",
    });

    const ctx = buildCtx(events, { delegation, agentDefinitions: definitions, spawnSession });

    let capturedQuestionId: string | undefined;
    const tools = createAskUserTool(ctx, "session-1", (qid) => {
      capturedQuestionId = qid;
    });

    // Use a 1-second timeout so the timer fires quickly
    const resultPromise = tools[0].execute({
      question: "Should we proceed?",
      timeout_seconds: 1,
      input_type: "text",
      multi_select: false,
      private: true,
    });

    // Wait for the timer to fire (1 second + a small buffer)
    const result = await resultPromise;
    const parsed = parseResult(result);

    // The answer should be the fallback agent's answer
    expect(parsed.answer).toBe("FallbackAgent auto-answer");

    // routing event must have been broadcast before spawn
    const routingEvents = events.filter((e) => e.type === "agent.question.routing");
    expect(routingEvents).toHaveLength(1);
    const routing = routingEvents[0];
    expect(routing.type).toBe("agent.question.routing");
    if (routing.type === "agent.question.routing") {
      expect(routing.targetAgentName).toBe("FallbackAgent");
      expect(routing.sessionId).toBe("session-1");
    }

    // resolved event must have been broadcast after spawn with isFallback: true
    const resolvedEvents = events.filter((e) => e.type === "agent.question.resolved");
    expect(resolvedEvents).toHaveLength(1);
    const resolved = resolvedEvents[0];
    expect(resolved.type).toBe("agent.question.resolved");
    if (resolved.type === "agent.question.resolved") {
      expect(resolved.isFallback).toBe(true);
      expect(resolved.answeredBy).toBe("FallbackAgent");
      expect(resolved.answer).toBe("FallbackAgent auto-answer");
      expect(resolved.sessionId).toBe("session-1");
    }

    // Question IDs must match across routing and resolved
    const routingQId = routingEvents[0].type === "agent.question.routing" ? routingEvents[0].questionId : null;
    const resolvedQId = resolvedEvents[0].type === "agent.question.resolved" ? resolvedEvents[0].questionId : null;
    expect(routingQId).toBe(resolvedQId);
  });

  test("ask_user in by_agents mode falls back to leastBusyAgent after timeout", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "by_agents" });

    const sessions = new SessionRegistry();
    sessions.create("session-1", { ...BASE_CONFIG, name: "Caller" });
    sessions.create("session-2", { ...BASE_CONFIG, name: "AnswerBot" });

    const definitions = new Map<string, AgentConfig>([
      ["AnswerBot", { ...BASE_CONFIG, name: "AnswerBot" }],
    ]);

    const spawnSession: ToolContext["spawnSession"] = async (sid) => ({
      sessionId: sid,
      result: "AnswerBot answer",
    });

    const ctx = buildCtx(events, { delegation, sessions, agentDefinitions: definitions, spawnSession });

    const tools = createAskUserTool(ctx, "session-1", undefined);
    const resultPromise = tools[0].execute({
      question: "Which approach is best?",
      timeout_seconds: 1,
      input_type: "text",
      multi_select: false,
      private: true,
    });

    const result = await resultPromise;
    const parsed = parseResult(result);

    expect(parsed.answer).toBe("AnswerBot answer");

    const routingEvent = events.find((e) => e.type === "agent.question.routing");
    expect(routingEvent).toBeDefined();
    if (routingEvent?.type === "agent.question.routing") {
      expect(routingEvent.targetAgentName).toBe("AnswerBot");
    }

    const resolvedEvent = events.find((e) => e.type === "agent.question.resolved");
    expect(resolvedEvent?.type).toBe("agent.question.resolved");
    if (resolvedEvent?.type === "agent.question.resolved") {
      expect(resolvedEvent.isFallback).toBe(true);
      expect(resolvedEvent.answeredBy).toBe("AnswerBot");
    }
  });

  test("ask_user in off mode resolves with timeout message when no human answer arrives", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "off" });

    const ctx = buildCtx(events, { delegation });

    const tools = createAskUserTool(ctx, "session-1", undefined);
    const resultPromise = tools[0].execute({
      question: "Are you there?",
      timeout_seconds: 1,
      input_type: "text",
      multi_select: false,
      private: true,
    });

    const result = await resultPromise;
    const parsed = parseResult(result);

    // Off mode: no agent routing, just the timeout fallback message
    expect(parsed.answer).toContain("did not respond");
    expect(events.filter((e) => e.type === "agent.question.routing")).toHaveLength(0);
    expect(events.filter((e) => e.type === "agent.question.resolved")).toHaveLength(0);
  });

  test("ask_user broadcasts agent.question event immediately with autoRouting=true in auto mode", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "specific_agent", targetAgentName: "Bot" });

    const definitions = new Map<string, AgentConfig>([
      ["Bot", { ...BASE_CONFIG, name: "Bot" }],
    ]);

    const ctx = buildCtx(events, { delegation, agentDefinitions: definitions });

    let questionIdFromCallback: string | undefined;
    const tools = createAskUserTool(ctx, "session-1", (qid) => {
      questionIdFromCallback = qid;
    });

    const resultPromise = tools[0].execute({
      question: "Auto route me?",
      timeout_seconds: 1,
      input_type: "text",
      multi_select: false,
      private: true,
    });

    // The agent.question event is broadcast synchronously inside the Promise constructor
    // before the timer fires, so we can check it immediately after starting the promise
    await new Promise((r) => setTimeout(r, 0));

    const questionEvent = events.find((e) => e.type === "agent.question");
    expect(questionEvent).toBeDefined();
    if (questionEvent?.type === "agent.question") {
      expect(questionEvent.autoRouting).toBe(true);
      expect(questionEvent.sessionId).toBe("session-1");
      expect(questionEvent.timeoutSeconds).toBe(1);
    }

    expect(questionIdFromCallback).toBeDefined();

    // Let the timer fire to clean up
    await resultPromise;
  });
});

// ─── Group 2: ask_agent end-to-end with real DelegationStore ─────────────────

describe("ask_agent — end-to-end with real DelegationStore", () => {
  test("off mode: nominated agent used, spawned with question", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "off" });

    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);

    let spawnedName = "";
    const spawnSession: ToolContext["spawnSession"] = async (sid, config) => {
      spawnedName = config.name;
      return { sessionId: sid, result: "LGTM" };
    };

    const ctx = buildCtx(events, { delegation, agentDefinitions: definitions, spawnSession });
    const result = await callAskAgent(ctx, "session-1", {
      question: "Is this code good?",
      to_agent: "Reviewer",
    });

    expect(spawnedName).toBe("Reviewer");
    expect(result.success).toBe(true);
    const parsed = parseResult(result);
    expect(parsed.answer).toBe("LGTM");

    const routingEvent = events.find((e) => e.type === "agent.question.routing");
    expect(routingEvent?.type).toBe("agent.question.routing");
    if (routingEvent?.type === "agent.question.routing") {
      expect(routingEvent.targetAgentName).toBe("Reviewer");
    }
  });

  test("specific_agent mode: target overridden regardless of nominated agent", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "specific_agent", targetAgentName: "PM" });

    const definitions = new Map<string, AgentConfig>([
      ["PM", { ...BASE_CONFIG, name: "PM" }],
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);

    let spawnedName = "";
    const spawnSession: ToolContext["spawnSession"] = async (sid, config) => {
      spawnedName = config.name;
      return { sessionId: sid, result: "PM says approved" };
    };

    const ctx = buildCtx(events, { delegation, agentDefinitions: definitions, spawnSession });
    const result = await callAskAgent(ctx, "session-1", {
      question: "Can we ship?",
      to_agent: "Reviewer", // overridden to PM by specific_agent mode
    });

    expect(spawnedName).toBe("PM");
    const parsed = parseResult(result);
    expect(parsed.answer).toBe("PM says approved");

    const routingEvent = events.find((e) => e.type === "agent.question.routing");
    if (routingEvent?.type === "agent.question.routing") {
      expect(routingEvent.targetAgentName).toBe("PM");
    }
  });

  test("coordinator mode: coordinator name used, overrides nominated agent", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "coordinator", targetAgentName: "Coordinator" });

    const definitions = new Map<string, AgentConfig>([
      ["Coordinator", { ...BASE_CONFIG, name: "Coordinator" }],
    ]);

    let spawnedName = "";
    const spawnSession: ToolContext["spawnSession"] = async (sid, config) => {
      spawnedName = config.name;
      return { sessionId: sid, result: "Coordinated" };
    };

    const ctx = buildCtx(events, { delegation, agentDefinitions: definitions, spawnSession });
    const result = await callAskAgent(ctx, "session-1", {
      question: "Next steps?",
      to_agent: "SomeOtherAgent",
    });

    expect(spawnedName).toBe("Coordinator");
    const parsed = parseResult(result);
    expect(parsed.answer).toBe("Coordinated");
  });

  test("by_agents mode: nominated agent used, not redirected", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "by_agents" });

    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);

    let spawnedName = "";
    const spawnSession: ToolContext["spawnSession"] = async (sid, config) => {
      spawnedName = config.name;
      return { sessionId: sid, result: "looks good" };
    };

    const ctx = buildCtx(events, { delegation, agentDefinitions: definitions, spawnSession });
    await callAskAgent(ctx, "session-1", {
      question: "Review this?",
      to_agent: "Reviewer",
    });

    // by_agents mode passes through the nominated agent unchanged
    expect(spawnedName).toBe("Reviewer");
  });

  test("by_agents mode with no targetAgentName falls back to nominated via resolveTarget", async () => {
    // by_agents mode: resolveTarget returns nominated (not undefined), so as long as
    // agentDefinitions has that agent, it gets spawned
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "by_agents" }); // no targetAgentName

    const definitions = new Map<string, AgentConfig>([
      ["DevAgent", { ...BASE_CONFIG, name: "DevAgent" }],
    ]);

    let spawnedName = "";
    const spawnSession: ToolContext["spawnSession"] = async (sid, config) => {
      spawnedName = config.name;
      return { sessionId: sid, result: "done" };
    };

    const events: SidecarEvent[] = [];
    const ctx = buildCtx(events, { delegation, agentDefinitions: definitions, spawnSession });
    await callAskAgent(ctx, "session-1", {
      question: "Help?",
      to_agent: "DevAgent",
    });

    expect(spawnedName).toBe("DevAgent");
  });

  test("routing event fires before spawn; resolved event fires after with correct questionId linkage", async () => {
    const events: SidecarEvent[] = [];
    const definitions = new Map<string, AgentConfig>([
      ["Agent", { ...BASE_CONFIG, name: "Agent" }],
    ]);

    const spawnOrder: string[] = [];
    const spawnSession: ToolContext["spawnSession"] = async (sid) => {
      spawnOrder.push("spawn");
      return { sessionId: sid, result: "answer" };
    };
    const broadcast = (e: SidecarEvent) => {
      if (e.type === "agent.question.routing") spawnOrder.push("routing");
      if (e.type === "agent.question.resolved") spawnOrder.push("resolved");
      events.push(e);
    };

    const ctx = buildCtx(events, { agentDefinitions: definitions, spawnSession, broadcast });
    await callAskAgent(ctx, "caller", { question: "Q?", to_agent: "Agent" });

    expect(spawnOrder).toEqual(["routing", "spawn", "resolved"]);

    const routingQId =
      events.find((e) => e.type === "agent.question.routing")?.type === "agent.question.routing"
        ? (events.find((e) => e.type === "agent.question.routing") as any).questionId
        : null;
    const resolvedQId =
      events.find((e) => e.type === "agent.question.resolved")?.type === "agent.question.resolved"
        ? (events.find((e) => e.type === "agent.question.resolved") as any).questionId
        : null;
    expect(routingQId).toBeDefined();
    expect(routingQId).toBe(resolvedQId);
  });

  test("resolved event has isFallback:false for direct ask_agent delegation", async () => {
    const events: SidecarEvent[] = [];
    const definitions = new Map<string, AgentConfig>([
      ["Target", { ...BASE_CONFIG, name: "Target" }],
    ]);
    const ctx = buildCtx(events, {
      agentDefinitions: definitions,
      spawnSession: async (sid) => ({ sessionId: sid, result: "direct answer" }),
    });

    await callAskAgent(ctx, "caller", { question: "Q?", to_agent: "Target" });

    const resolvedEvent = events.find((e) => e.type === "agent.question.resolved");
    expect(resolvedEvent?.type).toBe("agent.question.resolved");
    if (resolvedEvent?.type === "agent.question.resolved") {
      expect(resolvedEvent.isFallback).toBe(false);
    }
  });

  test("DelegationStore.resolveTarget + leastBusyAgent produce correct fallback agent for by_agents", () => {
    const delegation = new DelegationStore();
    delegation.set("session-x", { mode: "by_agents" });

    const sessions = new SessionRegistry();
    sessions.create("session-x", { ...BASE_CONFIG, name: "Caller" });
    sessions.create("session-y", { ...BASE_CONFIG, name: "Helper" });

    const messages = new MessageStore();
    const ctx = buildCtx([], { delegation, sessions, messages });

    // resolveTarget for by_agents with no nominated agent returns undefined
    const resolved = delegation.resolveTarget("session-x", undefined);
    expect(resolved).toBeUndefined();

    // leastBusyAgent finds the other active session
    const fallback = leastBusyAgent(ctx, "session-x");
    expect(fallback).toBe("session-y");

    const fallbackState = sessions.get(fallback!);
    expect(fallbackState?.agentName).toBe("Helper");
  });
});

// ─── Group 3: session teardown cleans delegation config ───────────────────────

describe("DelegationStore — session teardown", () => {
  test("delete removes the session config; subsequent resolveTarget returns off-mode behavior", () => {
    const delegation = new DelegationStore();

    delegation.set("session-1", { mode: "specific_agent", targetAgentName: "PM" });
    expect(delegation.resolveTarget("session-1", "Reviewer")).toBe("PM");

    delegation.delete("session-1");

    // After deletion, get() returns default {mode: "off"}, so resolveTarget
    // returns the nominated agent unchanged (off mode passthrough)
    expect(delegation.resolveTarget("session-1", "Reviewer")).toBe("Reviewer");
  });

  test("delete removes only the target session; other sessions are unaffected", () => {
    const delegation = new DelegationStore();

    delegation.set("session-1", { mode: "coordinator", targetAgentName: "Coord" });
    delegation.set("session-2", { mode: "specific_agent", targetAgentName: "PM" });

    delegation.delete("session-1");

    // session-1 is gone → default off behavior
    expect(delegation.resolveTarget("session-1", "Reviewer")).toBe("Reviewer");

    // session-2 is untouched
    expect(delegation.resolveTarget("session-2", "Reviewer")).toBe("PM");
  });

  test("ask_agent after session teardown uses nominated agent (off mode fallback)", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();

    // Configure override, then tear down
    delegation.set("session-1", { mode: "specific_agent", targetAgentName: "PM" });
    delegation.delete("session-1");

    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
      ["PM", { ...BASE_CONFIG, name: "PM" }],
    ]);

    let spawnedName = "";
    const spawnSession: ToolContext["spawnSession"] = async (sid, config) => {
      spawnedName = config.name;
      return { sessionId: sid, result: "answer from Reviewer" };
    };

    const ctx = buildCtx(events, { delegation, agentDefinitions: definitions, spawnSession });
    const result = await callAskAgent(ctx, "session-1", {
      question: "LGTM?",
      to_agent: "Reviewer",
    });

    // After teardown, PM override is gone — Reviewer should be used
    expect(spawnedName).toBe("Reviewer");
    const parsed = parseResult(result);
    expect(parsed.answer).toBe("answer from Reviewer");
  });

  test("multiple delete calls on the same session id are idempotent", () => {
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "by_agents" });

    delegation.delete("session-1");
    expect(() => delegation.delete("session-1")).not.toThrow();

    // Still off-mode after double delete
    expect(delegation.get("session-1").mode).toBe("off");
  });

  test("deleting a non-existent session does not throw", () => {
    const delegation = new DelegationStore();
    expect(() => delegation.delete("never-existed")).not.toThrow();
    expect(delegation.resolveTarget("never-existed", "SomeAgent")).toBe("SomeAgent");
  });
});
