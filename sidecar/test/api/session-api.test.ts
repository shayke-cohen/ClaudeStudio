import { afterEach, describe, test, expect } from "bun:test";
import { handleApiRequest } from "../../src/api-router.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { SseManager } from "../../src/sse-manager.js";
import { WebhookManager } from "../../src/webhook-manager.js";
import type { ApiContext } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { SidecarEvent } from "../../src/types.js";
import { makeAgentConfig } from "../helpers.js";

const BASE = "http://localhost/api/v1";

type ResumeCall = { sessionId: string; claudeSessionId: string };
type SpawnCall = { sessionId: string; config: any; prompt: string; waitForResult: boolean };
const activeSseManagers: SseManager[] = [];

function makeContext() {
  const sessions = new SessionRegistry();
  const sseManager = new SseManager();
  const pauseCalls: string[] = [];
  const resumeCalls: ResumeCall[] = [];
  const spawnCalls: SpawnCall[] = [];

  const toolCtx: ToolContext = {
    blackboard: new BlackboardStore(`session-api-${Date.now()}`),
    taskBoard: new TaskBoardStore(`session-api-${Date.now()}`),
    sessions,
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
    broadcast: (event: SidecarEvent) => sseManager.broadcast(event),
    agentDefinitions: new Map(),
    spawnSession: async (sessionId) => ({ sessionId }),
  };

  const sessionManager = {
    pauseSession: async (sessionId: string) => {
      pauseCalls.push(sessionId);
      sessions.update(sessionId, { status: "paused" });
    },
    resumeSession: async (sessionId: string, claudeSessionId: string) => {
      resumeCalls.push({ sessionId, claudeSessionId });
      sessions.update(sessionId, { status: "active", claudeSessionId });
    },
    listSessions: () => sessions.list(),
    spawnAutonomous: async (sessionId: string, config: any, prompt: string, waitForResult: boolean) => {
      spawnCalls.push({ sessionId, config, prompt, waitForResult });
      return { sessionId };
    },
  } as any;

  const ctx: ApiContext = {
    sessionManager,
    toolCtx,
    sseManager,
    webhookManager: new WebhookManager(),
  };

  activeSseManagers.push(sseManager);

  return { ctx, sessions, sseManager, pauseCalls, resumeCalls, spawnCalls };
}

async function readChunk(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  timeoutMs = 1000,
): Promise<string | null> {
  const timeout = new Promise<null>((resolve) => {
    setTimeout(() => resolve(null), timeoutMs);
  });
  const read = reader.read().then(({ value, done }) => {
    if (done || !value) return null;
    if (typeof value === "string") return value;
    if (value instanceof Uint8Array) return new TextDecoder().decode(value);
    if (value instanceof ArrayBuffer) return new TextDecoder().decode(new Uint8Array(value));
    return new TextDecoder().decode(new Uint8Array(value as ArrayBufferLike));
  });

  return Promise.race([read, timeout]);
}

afterEach(() => {
  while (activeSseManagers.length > 0) {
    activeSseManagers.pop()?.close();
  }
});

describe("Session API recovery routes", () => {
  test.each([
    { provider: "claude", model: "claude-sonnet-4-6" },
    { provider: "claude", model: "ollama:qwen3-coder:latest" },
    { provider: "codex", model: "gpt-5-codex" },
  ])("POST /sessions preserves $provider provider on spawned session config", async ({ provider, model }) => {
    const { ctx, spawnCalls } = makeContext();
    ctx.toolCtx.agentDefinitions.set(`${provider}-agent`, makeAgentConfig({
      name: `${provider}-agent`,
      provider,
      model,
      workingDirectory: `/tmp/${provider}-agent`,
    }));

    const response = await handleApiRequest(
      new Request(`${BASE}/sessions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          agentName: `${provider}-agent`,
          message: `hello from ${provider}`,
          waitForResult: false,
        }),
      }),
      ctx,
    );

    expect(response?.status).toBe(201);
    const body = await response?.json() as any;
    expect(body.agentName).toBe(`${provider}-agent`);
    expect(body.provider).toBe(provider);
    expect(spawnCalls).toHaveLength(1);
    expect(spawnCalls[0]?.config.provider).toBe(provider);
    expect(spawnCalls[0]?.config.model).toBe(model);
    expect(spawnCalls[0]?.prompt).toBe(`hello from ${provider}`);
  });

  test.each([
    { provider: "claude", model: "claude-sonnet-4-6" },
    { provider: "claude", model: "ollama:qwen3-coder:latest" },
    { provider: "codex", model: "gpt-5-codex" },
  ])("agent endpoints expose $provider provider metadata", async ({ provider, model }) => {
    const { ctx } = makeContext();
    ctx.toolCtx.agentDefinitions.set(`${provider}-agent`, makeAgentConfig({
      name: `${provider}-agent`,
      provider,
      model,
      workingDirectory: `/tmp/${provider}-agent`,
    }));

    const getResponse = await handleApiRequest(
      new Request(`${BASE}/agents/${provider}-agent`, { method: "GET" }),
      ctx,
    );
    expect(getResponse?.status).toBe(200);
    const agentBody = await getResponse?.json() as any;
    expect(agentBody.name).toBe(`${provider}-agent`);
    expect(agentBody.provider).toBe(provider);
    expect(agentBody.model).toBe(model);

    const listResponse = await handleApiRequest(
      new Request(`${BASE}/agents`, { method: "GET" }),
      ctx,
    );
    expect(listResponse?.status).toBe(200);
    const listBody = await listResponse?.json() as any;
    expect(listBody.agents).toEqual([
      expect.objectContaining({
        name: `${provider}-agent`,
        provider,
        model,
      }),
    ]);
  });

  test.each([
    { provider: "claude", model: "claude-sonnet-4-6" },
    { provider: "claude", model: "ollama:qwen3-coder:latest" },
    { provider: "codex", model: "gpt-5-codex" },
  ])("session endpoints expose $provider provider metadata", async ({ provider, model }) => {
    const { ctx, sessions } = makeContext();
    const sessionId = `${provider}-session`;
    sessions.create(sessionId, makeAgentConfig({
      name: `${provider}-agent`,
      provider,
      model,
      workingDirectory: `/tmp/${provider}-session`,
    }));

    const getResponse = await handleApiRequest(
      new Request(`${BASE}/sessions/${sessionId}`, { method: "GET" }),
      ctx,
    );
    expect(getResponse?.status).toBe(200);
    const sessionBody = await getResponse?.json() as any;
    expect(sessionBody.id).toBe(sessionId);
    expect(sessionBody.agentName).toBe(`${provider}-agent`);
    expect(sessionBody.provider).toBe(provider);
    expect(sessions.get(sessionId)?.provider).toBe(provider);
    expect(sessions.getConfig(sessionId)?.model).toBe(model);

    const listResponse = await handleApiRequest(
      new Request(`${BASE}/sessions`, { method: "GET" }),
      ctx,
    );
    expect(listResponse?.status).toBe(200);
    const listBody = await listResponse?.json() as any;
    expect(listBody.sessions).toEqual([
      expect.objectContaining({
        id: sessionId,
        agentName: `${provider}-agent`,
        provider,
      }),
    ]);
  });

  test("POST /sessions/:id/resume uses stored claudeSessionId when body is empty", async () => {
    const { ctx, sessions, resumeCalls } = makeContext();
    sessions.create("stored-session", makeAgentConfig({ name: "StoredResumeBot" }));
    sessions.update("stored-session", { claudeSessionId: "stored-claude", status: "paused" });

    const response = await handleApiRequest(
      new Request(`${BASE}/sessions/stored-session/resume`, { method: "POST" }),
      ctx,
    );

    expect(response?.status).toBe(200);
    expect(await response?.json()).toEqual({
      sessionId: "stored-session",
      status: "active",
      restored: true,
    });
    expect(resumeCalls).toEqual([
      { sessionId: "stored-session", claudeSessionId: "stored-claude" },
    ]);
  });

  test("POST /sessions/:id/resume lets request body override the stored claudeSessionId", async () => {
    const { ctx, sessions, resumeCalls } = makeContext();
    sessions.create("override-session", makeAgentConfig({ name: "OverrideResumeBot" }));
    sessions.update("override-session", { claudeSessionId: "stored-claude" });

    const response = await handleApiRequest(
      new Request(`${BASE}/sessions/override-session/resume`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ claudeSessionId: "override-claude" }),
      }),
      ctx,
    );

    expect(response?.status).toBe(200);
    expect(resumeCalls).toEqual([
      { sessionId: "override-session", claudeSessionId: "override-claude" },
    ]);
    expect(sessions.get("override-session")?.claudeSessionId).toBe("override-claude");
  });

  test("POST /sessions/:id/resume returns 404 for unknown sessions", async () => {
    const { ctx } = makeContext();

    const response = await handleApiRequest(
      new Request(`${BASE}/sessions/missing-session/resume`, { method: "POST" }),
      ctx,
    );

    expect(response?.status).toBe(404);
    const body = await response?.json() as any;
    expect(body.error).toBe("session_not_found");
  });

  test("POST /sessions/:id/resume returns 400 when no claudeSessionId is available", async () => {
    const { ctx, sessions, resumeCalls } = makeContext();
    sessions.create("no-claude-session", makeAgentConfig({ name: "NoClaudeBot" }));

    const response = await handleApiRequest(
      new Request(`${BASE}/sessions/no-claude-session/resume`, { method: "POST" }),
      ctx,
    );

    expect(response?.status).toBe(400);
    const body = await response?.json() as any;
    expect(body.error).toBe("invalid_request");
    expect(resumeCalls).toHaveLength(0);
  });

  test("pause then resume returns the expected status payloads", async () => {
    const { ctx, sessions, pauseCalls, resumeCalls } = makeContext();
    sessions.create("pause-resume-session", makeAgentConfig({ name: "PauseResumeBot" }));
    sessions.update("pause-resume-session", { claudeSessionId: "pause-resume-claude" });

    const pauseResponse = await handleApiRequest(
      new Request(`${BASE}/sessions/pause-resume-session/pause`, { method: "POST" }),
      ctx,
    );
    expect(pauseResponse?.status).toBe(200);
    expect(await pauseResponse?.json()).toEqual({
      sessionId: "pause-resume-session",
      status: "paused",
    });
    expect(pauseCalls).toEqual(["pause-resume-session"]);
    expect(sessions.get("pause-resume-session")?.status).toBe("paused");

    const resumeResponse = await handleApiRequest(
      new Request(`${BASE}/sessions/pause-resume-session/resume`, { method: "POST" }),
      ctx,
    );
    expect(resumeResponse?.status).toBe(200);
    expect(await resumeResponse?.json()).toEqual({
      sessionId: "pause-resume-session",
      status: "active",
      restored: true,
    });
    expect(resumeCalls).toEqual([
      { sessionId: "pause-resume-session", claudeSessionId: "pause-resume-claude" },
    ]);
    expect(sessions.get("pause-resume-session")?.status).toBe("active");
  });

  test("SSE reconnect does not replay old events", async () => {
    const { ctx, sessions, sseManager } = makeContext();
    sessions.create("sse-session", makeAgentConfig({ name: "SseBot" }));

    const firstResponse = await handleApiRequest(
      new Request(`${BASE}/sessions/sse-session/events`, { method: "GET" }),
      ctx,
    );
    expect(firstResponse?.status).toBe(200);
    const firstReader = firstResponse?.body?.getReader();
    expect(firstReader).toBeDefined();
    const firstConnected = await readChunk(firstReader!);
    expect(firstConnected).toContain(`"sessionId":"sse-session"`);

    sseManager.broadcast({
      type: "stream.token",
      sessionId: "sse-session",
      text: "before-reconnect",
    });
    const firstEvent = await readChunk(firstReader!);
    expect(firstEvent).toContain("before-reconnect");

    await firstReader?.cancel();

    const secondResponse = await handleApiRequest(
      new Request(`${BASE}/sessions/sse-session/events`, { method: "GET" }),
      ctx,
    );
    expect(secondResponse?.status).toBe(200);
    const secondReader = secondResponse?.body?.getReader();
    expect(secondReader).toBeDefined();
    const secondConnected = await readChunk(secondReader!);
    expect(secondConnected).toContain(`"sessionId":"sse-session"`);

    sseManager.broadcast({
      type: "stream.token",
      sessionId: "sse-session",
      text: "after-reconnect",
    });
    const secondEvent = await readChunk(secondReader!);
    expect(secondEvent).not.toBeNull();
    expect(String(secondEvent)).toContain("after-reconnect");
    expect(String(secondEvent)).not.toContain("before-reconnect");

    await secondReader?.cancel();
    sseManager.close();
  });
});
