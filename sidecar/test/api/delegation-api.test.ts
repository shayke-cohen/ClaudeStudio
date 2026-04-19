/**
 * API tests for delegation-related endpoints and WS command handling.
 *
 * Covers:
 * - POST /api/v1/sessions/:id/questions/:qid/answer  — resolves a pending question
 * - POST /api/v1/sessions/:id/questions              — creates a question (long-poll pattern)
 * - conversation.setDelegationMode WS command        — updates DelegationStore
 * - DELETE /api/v1/sessions/:id                      — cleans up delegation config
 *
 * Usage: bun test test/api/delegation-api.test.ts
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
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { DelegationStore } from "../../src/stores/delegation-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import { SseManager } from "../../src/sse-manager.js";
import { WebhookManager } from "../../src/webhook-manager.js";
import { WsServer } from "../../src/ws-server.js";
import { pendingQuestions, createQuestion, resolveQuestion } from "../../src/tools/ask-user-tool.js";
import type { ApiContext } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { SidecarEvent, AgentConfig } from "../../src/types.js";
import { makeAgentConfig } from "../helpers.js";
import { wsConnectDirect } from "../helpers.js";

const BASE = "http://localhost/api/v1";
const activeSseManagers: SseManager[] = [];

// ─── Context factory ─────────────────────────────────────────────────

function makeContext() {
  const sessions = new SessionRegistry();
  const delegation = new DelegationStore();
  const sseManager = new SseManager();
  const broadcastEvents: SidecarEvent[] = [];

  const toolCtx: ToolContext = {
    blackboard: new BlackboardStore(`delegation-api-${Date.now()}`),
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
    delegation,
    broadcast: (event: SidecarEvent) => {
      broadcastEvents.push(event);
      sseManager.broadcast(event);
    },
    agentDefinitions: new Map<string, AgentConfig>(),
    spawnSession: async (sessionId) => ({ sessionId }),
  };

  const sessionManager = {
    pauseSession: async (sessionId: string) => {
      sessions.update(sessionId, { status: "paused" });
    },
    resumeSession: async (sessionId: string, claudeSessionId: string) => {
      sessions.update(sessionId, { status: "active", claudeSessionId });
    },
    listSessions: () => sessions.list(),
    spawnAutonomous: async (sessionId: string, config: any, _prompt: string, _wait: boolean) => {
      sessions.create(sessionId, config);
      return { sessionId };
    },
    sendMessage: async () => {},
    forkSession: async () => {},
  } as any;

  const ctx: ApiContext = {
    sessionManager,
    toolCtx,
    sseManager,
    webhookManager: new WebhookManager(),
  };

  activeSseManagers.push(sseManager);
  return { ctx, sessions, delegation, broadcastEvents, sseManager };
}

afterEach(() => {
  while (activeSseManagers.length > 0) {
    activeSseManagers.pop()?.close();
  }
});

// ─── POST /sessions/:id/questions/:qid/answer ────────────────────────

describe("POST /sessions/:id/questions/:qid/answer", () => {
  test("resolves a pending question and returns resolved: true", async () => {
    const { ctx, sessions } = makeContext();
    sessions.create("q-session", makeAgentConfig({ name: "QuestionBot" }));

    // Register a pending question directly via the shared store
    const { questionId, promise } = createQuestion("q-session");

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions/q-session/questions/${questionId}/answer`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ answer: "yes" }),
      }),
      ctx,
    );

    expect(res?.status).toBe(200);
    const body = await res?.json() as any;
    expect(body.resolved).toBe(true);
    expect(body.questionId).toBe(questionId);

    // The promise should resolve with the provided answer
    const result = await promise;
    expect(result.answer).toBe("yes");
    expect(result.selectedOptions).toBeUndefined();
  });

  test("passes selectedOptions through to the resolver", async () => {
    const { ctx, sessions } = makeContext();
    sessions.create("opts-session", makeAgentConfig({ name: "OptionsBot" }));

    const { questionId, promise } = createQuestion("opts-session");

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions/opts-session/questions/${questionId}/answer`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ answer: "Option A", selectedOptions: ["Option A", "Option C"] }),
      }),
      ctx,
    );

    expect(res?.status).toBe(200);
    const body = await res?.json() as any;
    expect(body.resolved).toBe(true);

    const result = await promise;
    expect(result.answer).toBe("Option A");
    expect(result.selectedOptions).toEqual(["Option A", "Option C"]);
  });

  test("returns 404 when no pending question exists for the given qid", async () => {
    const { ctx, sessions } = makeContext();
    sessions.create("missing-q-session", makeAgentConfig({ name: "MissingQBot" }));

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions/missing-q-session/questions/non-existent-qid/answer`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ answer: "anything" }),
      }),
      ctx,
    );

    expect(res?.status).toBe(404);
    const body = await res?.json() as any;
    expect(body.error).toBe("question_not_found");
  });

  test("returns 400 when answer field is missing from body", async () => {
    const { ctx, sessions } = makeContext();
    sessions.create("bad-body-session", makeAgentConfig({ name: "BadBodyBot" }));

    const { questionId } = createQuestion("bad-body-session");
    // clean up to avoid leaking a pending promise
    resolveQuestion(questionId, "cleanup");

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions/bad-body-session/questions/any-qid/answer`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ selectedOptions: ["only-options"] }), // no answer field
      }),
      ctx,
    );

    expect(res?.status).toBe(400);
    const body = await res?.json() as any;
    expect(body.error).toBe("invalid_request");
  });

  test("a question can only be resolved once", async () => {
    const { ctx, sessions } = makeContext();
    sessions.create("one-shot-session", makeAgentConfig({ name: "OneShotBot" }));

    const { questionId } = createQuestion("one-shot-session");

    // First answer resolves it
    const res1 = await handleApiRequest(
      new Request(`${BASE}/sessions/one-shot-session/questions/${questionId}/answer`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ answer: "first" }),
      }),
      ctx,
    );
    expect(res1?.status).toBe(200);

    // Second answer for the same qid finds nothing
    const res2 = await handleApiRequest(
      new Request(`${BASE}/sessions/one-shot-session/questions/${questionId}/answer`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ answer: "second" }),
      }),
      ctx,
    );
    expect(res2?.status).toBe(404);
    const body = await res2?.json() as any;
    expect(body.error).toBe("question_not_found");
  });
});

// ─── POST /sessions/:id/questions (create + long-poll) ───────────────

describe("POST /sessions/:id/questions", () => {
  test("creates a question and broadcasts agent.question event", async () => {
    const { ctx, sessions, broadcastEvents } = makeContext();
    sessions.create("create-q-session", makeAgentConfig({ name: "CreateQBot" }));

    // The create endpoint long-polls — we need to answer concurrently so it resolves.
    let capturedQuestionId: string | null = null;
    const originalGet = pendingQuestions.get.bind(pendingQuestions);
    const checkInterval = setInterval(() => {
      const questionEvent = broadcastEvents.find((e) => e.type === "agent.question");
      if (questionEvent && (questionEvent as any).questionId) {
        capturedQuestionId = (questionEvent as any).questionId;
        clearInterval(checkInterval);
        resolveQuestion(capturedQuestionId!, "auto-answer");
      }
    }, 5);

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions/create-q-session/questions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          question: "What should I do next?",
          options: [{ label: "Continue" }, { label: "Stop" }],
          multiSelect: false,
          private: true,
        }),
      }),
      ctx,
    );

    clearInterval(checkInterval);

    expect(res?.status).toBe(200);
    const body = await res?.json() as any;
    expect(body.questionId).toBeDefined();
    expect(body.answer).toBe("auto-answer");

    // agent.question event was broadcast
    const questionEvent = broadcastEvents.find((e) => e.type === "agent.question") as any;
    expect(questionEvent).toBeDefined();
    expect(questionEvent.sessionId).toBe("create-q-session");
    expect(questionEvent.question).toBe("What should I do next?");
  });

  test("returns 400 when question field is missing", async () => {
    const { ctx, sessions } = makeContext();
    sessions.create("no-q-session", makeAgentConfig({ name: "NoQBot" }));

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions/no-q-session/questions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ options: [{ label: "A" }] }),
      }),
      ctx,
    );

    expect(res?.status).toBe(400);
    const body = await res?.json() as any;
    expect(body.error).toBe("invalid_request");
  });
});

// ─── conversation.setDelegationMode WS command ───────────────────────

describe("conversation.setDelegationMode WS command", () => {
  const WS_PORT = 19849 + Math.floor(Math.random() * 800);

  test("sets delegation mode in DelegationStore", async () => {
    const delegation = new DelegationStore();
    const sessions = new SessionRegistry();
    const broadcastedEvents: SidecarEvent[] = [];

    const toolCtx: ToolContext = {
      blackboard: new BlackboardStore(`ws-deleg-${Date.now()}`),
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
      delegation,
      broadcast: (event: SidecarEvent) => { broadcastedEvents.push(event); },
      agentDefinitions: new Map(),
      spawnSession: async (sessionId) => ({ sessionId }),
    };

    const mockSessionManager = {
      createSession: async () => {},
      sendMessage: async () => {},
      resumeSession: async () => {},
      forkSession: async () => {},
      pauseSession: async () => {},
      bulkResume: async () => {},
      updateSessionMode: () => {},
      updateSessionCwd: () => {},
    } as any;

    const wsServer = new WsServer(WS_PORT, mockSessionManager, toolCtx);
    const ws = await wsConnectDirect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      // Before command: no delegation config
      expect(delegation.get("conv-123")).toEqual({ mode: "off" });

      ws.send({
        type: "conversation.setDelegationMode",
        sessionId: "conv-123",
        mode: "specific_agent",
        targetAgentName: "ReviewBot",
      });

      // Give the handler time to run
      await new Promise((resolve) => setTimeout(resolve, 50));

      const config = delegation.get("conv-123");
      expect(config.mode).toBe("specific_agent");
      expect(config.targetAgentName).toBe("ReviewBot");
    } finally {
      ws.close();
      wsServer.close();
    }
  });

  test("overwrites existing delegation config", async () => {
    const delegation = new DelegationStore();
    delegation.set("conv-456", { mode: "by_agents" });

    const toolCtx: ToolContext = {
      blackboard: new BlackboardStore(`ws-deleg2-${Date.now()}`),
      sessions: new SessionRegistry(),
      messages: new MessageStore(),
      channels: new ChatChannelStore(),
      workspaces: new WorkspaceStore(),
      peerRegistry: new PeerRegistry(),
      connectors: new ConnectorStore(),
      conversationStore: new ConversationStore(),
      projectStore: new ProjectStore(),
      nostrTransport: new NostrTransport(() => {}),
      relayClient: { isConnected: () => false, connect: async () => {}, sendCommand: async () => ({}) } as any,
      delegation,
      broadcast: () => {},
      agentDefinitions: new Map(),
      spawnSession: async (sessionId) => ({ sessionId }),
    };

    const WS_PORT_2 = WS_PORT + 100;
    const mockSessionManager = {
      createSession: async () => {},
      sendMessage: async () => {},
      resumeSession: async () => {},
      forkSession: async () => {},
      pauseSession: async () => {},
      bulkResume: async () => {},
      updateSessionMode: () => {},
      updateSessionCwd: () => {},
    } as any;

    const wsServer = new WsServer(WS_PORT_2, mockSessionManager, toolCtx);
    const ws = await wsConnectDirect(WS_PORT_2);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "conversation.setDelegationMode",
        sessionId: "conv-456",
        mode: "coordinator",
        targetAgentName: "OrchestratorBot",
      });

      await new Promise((resolve) => setTimeout(resolve, 50));

      const config = delegation.get("conv-456");
      expect(config.mode).toBe("coordinator");
      expect(config.targetAgentName).toBe("OrchestratorBot");
    } finally {
      ws.close();
      wsServer.close();
    }
  });

  test("mode off clears targetAgentName when none provided", async () => {
    const delegation = new DelegationStore();
    delegation.set("conv-789", { mode: "specific_agent", targetAgentName: "OldBot" });

    const toolCtx: ToolContext = {
      blackboard: new BlackboardStore(`ws-deleg3-${Date.now()}`),
      sessions: new SessionRegistry(),
      messages: new MessageStore(),
      channels: new ChatChannelStore(),
      workspaces: new WorkspaceStore(),
      peerRegistry: new PeerRegistry(),
      connectors: new ConnectorStore(),
      conversationStore: new ConversationStore(),
      projectStore: new ProjectStore(),
      nostrTransport: new NostrTransport(() => {}),
      relayClient: { isConnected: () => false, connect: async () => {}, sendCommand: async () => ({}) } as any,
      delegation,
      broadcast: () => {},
      agentDefinitions: new Map(),
      spawnSession: async (sessionId) => ({ sessionId }),
    };

    const WS_PORT_3 = WS_PORT + 200;
    const mockSessionManager = {
      createSession: async () => {},
      sendMessage: async () => {},
      resumeSession: async () => {},
      forkSession: async () => {},
      pauseSession: async () => {},
      bulkResume: async () => {},
      updateSessionMode: () => {},
      updateSessionCwd: () => {},
    } as any;

    const wsServer = new WsServer(WS_PORT_3, mockSessionManager, toolCtx);
    const ws = await wsConnectDirect(WS_PORT_3);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "conversation.setDelegationMode",
        sessionId: "conv-789",
        mode: "off",
        // no targetAgentName
      });

      await new Promise((resolve) => setTimeout(resolve, 50));

      const config = delegation.get("conv-789");
      expect(config.mode).toBe("off");
      expect(config.targetAgentName).toBeUndefined();
    } finally {
      ws.close();
      wsServer.close();
    }
  });
});

// ─── DELETE /sessions/:id cleans up delegation config ─────────────────

describe("DELETE /sessions/:id", () => {
  test("removes delegation config for the deleted session", async () => {
    const { ctx, sessions, delegation } = makeContext();
    const sessionId = "del-session";
    sessions.create(sessionId, makeAgentConfig({ name: "DeleteBot" }));
    sessions.update(sessionId, { status: "paused" });

    // Pre-seed a delegation config for this session
    delegation.set(sessionId, { mode: "specific_agent", targetAgentName: "Reviewer" });
    expect(delegation.get(sessionId)).toEqual({ mode: "specific_agent", targetAgentName: "Reviewer" });

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions/${sessionId}`, { method: "DELETE" }),
      ctx,
    );

    expect(res?.status).toBe(200);
    const body = await res?.json() as any;
    expect(body.deleted).toBe(true);
    expect(body.sessionId).toBe(sessionId);

    // Delegation config must be gone — store returns default
    expect(delegation.get(sessionId)).toEqual({ mode: "off" });
  });

  test("delegation cleanup does not affect other sessions", async () => {
    const { ctx, sessions, delegation } = makeContext();

    sessions.create("session-a", makeAgentConfig({ name: "AgentA" }));
    sessions.update("session-a", { status: "paused" });
    sessions.create("session-b", makeAgentConfig({ name: "AgentB" }));

    delegation.set("session-a", { mode: "by_agents" });
    delegation.set("session-b", { mode: "coordinator", targetAgentName: "PM" });

    await handleApiRequest(
      new Request(`${BASE}/sessions/session-a`, { method: "DELETE" }),
      ctx,
    );

    // session-a config gone
    expect(delegation.get("session-a")).toEqual({ mode: "off" });
    // session-b config intact
    expect(delegation.get("session-b")).toEqual({ mode: "coordinator", targetAgentName: "PM" });
  });

  test("returns 409 when deleting an active session", async () => {
    const { ctx, sessions, delegation } = makeContext();
    sessions.create("active-session", makeAgentConfig({ name: "ActiveBot" }));
    // Active status is the default

    delegation.set("active-session", { mode: "by_agents" });

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions/active-session`, { method: "DELETE" }),
      ctx,
    );

    expect(res?.status).toBe(409);
    const body = await res?.json() as any;
    expect(body.error).toBe("session_not_active");

    // Delegation config must still be there — delete was rejected
    expect(delegation.get("active-session")).toEqual({ mode: "by_agents" });
  });

  test("returns 404 for unknown session", async () => {
    const { ctx } = makeContext();

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions/ghost-session`, { method: "DELETE" }),
      ctx,
    );

    expect(res?.status).toBe(404);
    const body = await res?.json() as any;
    expect(body.error).toBe("session_not_found");
  });
});
