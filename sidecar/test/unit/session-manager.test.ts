/**
 * Unit tests for SessionManager short-circuit paths.
 *
 * These avoid hitting real runtimes; they exercise the code paths that
 * short-circuit on missing sessions, missing configs, and mode updates.
 * Full lifecycle tests live in test/integration/local-agent-runtime.test.ts.
 */
import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { SessionManager } from "../../src/session-manager.js";
import { pendingQuestions, questionsBySession } from "../../src/tools/ask-user-tool.js";
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
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import { DelegationStore } from "../../src/stores/delegation-store.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";

function buildCtx(broadcast: (e: SidecarEvent) => void = () => {}): ToolContext {
  return {
    blackboard: new BlackboardStore(`sm-test-${Date.now()}-${Math.random()}`),
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
    broadcast,
    delegation: new DelegationStore(),
    pendingBrowserBlocking: new Map(),
    pendingBrowserResults: new Map(),
    spawnSession: async (sid) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
  };
}

describe("pauseSession — ask_user cleanup", () => {
  let events: SidecarEvent[];
  let registry: SessionRegistry;
  let ctx: ToolContext;
  let sm: SessionManager;

  beforeEach(() => {
    events = [];
    registry = new SessionRegistry();
    ctx = { ...buildCtx((e) => events.push(e)), sessions: registry };
    sm = new SessionManager((e) => events.push(e), registry, ctx);
  });

  afterEach(() => {
    pendingQuestions.clear();
    questionsBySession.clear();
  });

  test("pauseSession resolves pending ask_user questions with a pause message", async () => {
    const sessionId = "pause-q-session";
    registry.create(sessionId, {
      name: "QuestionBot",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/tmp",
      skills: [],
    });

    let resolvedAnswer: string | undefined;
    const questionId = "q-pause-test";
    pendingQuestions.set(questionId, {
      resolve: (result) => { resolvedAnswer = result.answer; },
      reject: () => {},
      timer: setTimeout(() => {}, 60_000),
    });
    questionsBySession.set(sessionId, new Set([questionId]));

    await sm.pauseSession(sessionId);

    expect(resolvedAnswer).toBe("[Session was paused before you could answer.]");
    expect(pendingQuestions.has(questionId)).toBe(false);
    expect(questionsBySession.has(sessionId)).toBe(false);
  });

  test("pauseSession resolves all pending questions when multiple are outstanding", async () => {
    const sessionId = "multi-q-session";
    registry.create(sessionId, {
      name: "MultiQBot",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/tmp",
      skills: [],
    });

    const answers: string[] = [];
    const ids = ["q1", "q2", "q3"];
    for (const id of ids) {
      pendingQuestions.set(id, {
        resolve: (result) => answers.push(result.answer),
        reject: () => {},
        timer: setTimeout(() => {}, 60_000),
      });
    }
    questionsBySession.set(sessionId, new Set(ids));

    await sm.pauseSession(sessionId);

    expect(answers).toHaveLength(3);
    expect(answers.every((a) => a === "[Session was paused before you could answer.]")).toBe(true);
    expect(pendingQuestions.size).toBe(0);
  });

  test("pauseSession on missing session does not throw and leaves questions untouched", async () => {
    const questionId = "q-untouched";
    pendingQuestions.set(questionId, {
      resolve: () => {},
      reject: () => {},
      timer: setTimeout(() => {}, 60_000),
    });

    await sm.pauseSession("ghost");

    expect(pendingQuestions.has(questionId)).toBe(true);
    pendingQuestions.delete(questionId);
  });

  test("session status is set to paused after pauseSession", async () => {
    const sessionId = "status-check-session";
    registry.create(sessionId, {
      name: "StatusBot",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/tmp",
      skills: [],
    });

    await sm.pauseSession(sessionId);

    expect(registry.get(sessionId)?.status).toBe("paused");
  });

  // spawnAutonomous(waitForResult=true) registers a Promise resolver in
  // autonomousResults. The resolver was only called from sendMessage's
  // success / error catch branches — never from the abort branch — so a
  // pause mid-turn left the awaited promise hanging forever.
  test("pauseSession resolves any pending autonomous-result waiter", async () => {
    const sessionId = "auto-waiter-session";
    registry.create(sessionId, {
      name: "AutoBot",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/tmp",
      skills: [],
    });

    let resolved = false;
    let resolvedValue: string | undefined;
    const waiterPromise = new Promise<string>((resolve) => {
      // Inject an autonomous-result waiter directly. spawnAutonomous would
      // create one of these for us, but mock runtime returns synchronously,
      // which would resolve the waiter before pauseSession could race.
      (sm as any).autonomousResults.set(sessionId, {
        resolve: (value: string) => {
          resolved = true;
          resolvedValue = value;
          resolve(value);
        },
      });
    });

    await sm.pauseSession(sessionId);

    // Pause should have resolved the waiter eagerly, not left it hanging.
    const raceResult = await Promise.race([
      waiterPromise.then(() => "resolved"),
      new Promise<string>((r) => setTimeout(() => r("hung"), 200)),
    ]);
    expect(raceResult).toBe("resolved");
    expect(resolved).toBe(true);
    expect(resolvedValue).toMatch(/paus/i);
    expect((sm as any).autonomousResults.has(sessionId)).toBe(false);
  });
});

describe("SessionManager short-circuit paths", () => {
  let events: SidecarEvent[];
  let registry: SessionRegistry;
  let ctx: ToolContext;
  let sm: SessionManager;

  beforeEach(() => {
    events = [];
    registry = new SessionRegistry();
    ctx = { ...buildCtx((e) => events.push(e)), sessions: registry };
    sm = new SessionManager((e) => events.push(e), registry, ctx);
  });

  test("sendMessage on unknown session emits session.error", async () => {
    await sm.sendMessage("ghost", "hi");
    expect(events).toHaveLength(1);
    expect(events[0]).toEqual({
      type: "session.error",
      sessionId: "ghost",
      error: "Session not found",
    });
  });

  test("updateSessionMode on missing session is a no-op", () => {
    sm.updateSessionMode("ghost", true);
    expect(registry.get("ghost")).toBeUndefined();
  });

  test("answerQuestion on missing session returns false", async () => {
    const result = await sm.answerQuestion("ghost", "q1", "yes");
    expect(result).toBe(false);
  });

  test("answerConfirmation on missing session returns false", async () => {
    const result = await sm.answerConfirmation("ghost", "c1", true);
    expect(result).toBe(false);
  });

  test("pauseSession on missing session does not throw", async () => {
    await sm.pauseSession("ghost");
  });

  test("buildQueryOptionsForTesting throws for unknown session", () => {
    expect(() => sm.buildQueryOptionsForTesting("ghost")).toThrow(
      /not found/,
    );
  });

  test("listSessions on empty registry returns []", () => {
    expect(sm.listSessions()).toEqual([]);
  });

  test("listSessions returns active sessions", () => {
    registry.create("s1", {
      name: "A",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/tmp",
      skills: [],
    });
    expect(sm.listSessions()).toHaveLength(1);
  });

  test("updateSessionCwd mutates registered config", () => {
    registry.create("s1", {
      name: "A",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/old",
      skills: [],
    });
    sm.updateSessionCwd("s1", "/new");
    expect(registry.getConfig("s1")?.workingDirectory).toBe("/new");
  });

  test("updateSessionMode updates interactive + policy on existing session", () => {
    registry.create("s1", {
      name: "A",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: "/tmp",
      skills: [],
    });
    sm.updateSessionMode("s1", false, "singleton", 3);
    const config = registry.getConfig("s1");
    expect(config?.interactive).toBe(false);
    expect(config?.instancePolicy).toBe("singleton");
    expect(config?.instancePolicyPoolMax).toBe(3);
  });
});
