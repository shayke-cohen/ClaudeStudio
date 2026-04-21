/**
 * API tests for POST /api/v1/generate/* endpoints.
 * Mocks @anthropic-ai/claude-agent-sdk so no real LLM calls are made.
 * The real GenerationService is used, which calls through to the mocked SDK.
 */
import { mock, describe, test, expect, beforeEach } from "bun:test";

// ─── Mock Agent SDK before imports ────────────────────────────────────────────

type QueryFn = (opts: any) => AsyncIterable<any>;
let mockQuery: QueryFn;

mock.module("@anthropic-ai/claude-agent-sdk", () => ({
  query: (opts: any) => mockQuery(opts),
}));

// Also stub the Anthropic SDK (used by the legacy /api/v1/agents/generate handler)
mock.module("@anthropic-ai/sdk", () => ({
  default: class {
    messages = { create: async () => ({ content: [{ type: "text", text: "{}" }] }) };
  },
}));

// ─── Imports (after mocks) ────────────────────────────────────────────────────

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
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import { SseManager } from "../../src/sse-manager.js";
import { WebhookManager } from "../../src/webhook-manager.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { ApiContext, AgentConfig } from "../../src/types.js";

// ─── Helpers ──────────────────────────────────────────────────────────────────

function buildCtx(): ApiContext {
  const toolCtx: ToolContext = {
    blackboard: new BlackboardStore(`gen-ep-${Date.now()}-${Math.random()}`),
    sessions: new SessionRegistry(),
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
    broadcast: () => {},
    spawnSession: async (sid: string) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
    pendingBrowserBlocking: new Map(),
    pendingBrowserResults: new Map(),
  };
  return {
    toolCtx,
    sessionManager: {
      listSessions: () => [],
      spawnAutonomous: async (id: string) => ({ sessionId: id }),
    } as any,
    sseManager: new SseManager(),
    webhookManager: new WebhookManager(),
  };
}

function post(path: string, body: object): Request {
  return new Request(`http://localhost:9850${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function sdkYields(json: object): void {
  mockQuery = async function* () {
    yield {
      type: "assistant",
      message: { content: [{ type: "text", text: JSON.stringify(json) }] },
    };
  };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("POST /api/v1/generate/template", () => {
  let ctx: ApiContext;

  beforeEach(() => { ctx = buildCtx(); });

  test("returns 201 with name and prompt", async () => {
    sdkYields({ name: "Review PR for Security", prompt: "Review {{pr_url}} for security issues." });
    const res = await handleApiRequest(post("/api/v1/generate/template", { intent: "review a PR for security" }), ctx);
    expect(res!.status).toBe(201);
    const body = await res!.json();
    expect(body.name).toBe("Review PR for Security");
    expect(body.prompt).toContain("security");
  });

  test("accepts optional agentName and agentSystemPrompt", async () => {
    let capturedOptions: any;
    mockQuery = function (opts: any) {
      capturedOptions = opts;
      return (async function* () {
        yield { type: "assistant", message: { content: [{ type: "text", text: '{"name":"Fix Bug","prompt":"Fix the bug."}' }] } };
      })();
    };
    const res = await handleApiRequest(post("/api/v1/generate/template", {
      intent: "fix a bug",
      agentName: "CodeBot",
      agentSystemPrompt: "You fix bugs.",
    }), ctx);
    expect(res!.status).toBe(201);
    expect(capturedOptions.options.systemPrompt.append).toContain("CodeBot");
    expect(capturedOptions.options.systemPrompt.append).toContain("You fix bugs.");
  });

  test("returns 400 when intent is missing", async () => {
    const res = await handleApiRequest(post("/api/v1/generate/template", {}), ctx);
    expect(res!.status).toBe(400);
    const body = await res!.json();
    expect(body.error).toBe("invalid_request");
  });

  test("returns 400 on invalid JSON body", async () => {
    const req = new Request("http://localhost:9850/api/v1/generate/template", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "not-json",
    });
    const res = await handleApiRequest(req, ctx);
    expect(res!.status).toBe(400);
  });
});

describe("POST /api/v1/generate/group", () => {
  let ctx: ApiContext;

  beforeEach(() => { ctx = buildCtx(); });

  test("returns 201 with group fields", async () => {
    sdkYields({
      name: "Security Team",
      description: "Focused on security.",
      icon: "🛡️",
      color: "blue",
      groupInstruction: "Work together to find vulnerabilities.",
      defaultMission: null,
      matchedAgentIds: [],
    });
    const res = await handleApiRequest(post("/api/v1/generate/group", { prompt: "a security team" }), ctx);
    expect(res!.status).toBe(201);
    const body = await res!.json();
    expect(body.name).toBe("Security Team");
    expect(body.groupInstruction).toBeTruthy();
  });

  test("falls back to blue for unrecognized color", async () => {
    sdkYields({ name: "My Group", groupInstruction: "Do stuff.", color: "rainbow", icon: "🌈", matchedAgentIds: [] });
    const res = await handleApiRequest(post("/api/v1/generate/group", { prompt: "some group" }), ctx);
    expect(res!.status).toBe(201);
    const body = await res!.json();
    expect(body.color).toBe("blue");
  });

  test("returns 400 when prompt is missing", async () => {
    const res = await handleApiRequest(post("/api/v1/generate/group", {}), ctx);
    expect(res!.status).toBe(400);
  });
});

describe("POST /api/v1/generate/skill", () => {
  let ctx: ApiContext;

  beforeEach(() => { ctx = buildCtx(); });

  test("returns 201 with skill fields", async () => {
    sdkYields({
      name: "Code Review",
      description: "Reviews code for quality.",
      category: "Code Review",
      triggers: ["review code", "check quality"],
      matchedMCPIds: [],
      content: "## Code Review\nAlways check for...",
    });
    const res = await handleApiRequest(post("/api/v1/generate/skill", { prompt: "code review skill" }), ctx);
    expect(res!.status).toBe(201);
    const body = await res!.json();
    expect(body.name).toBe("Code Review");
    expect(body.content).toBeTruthy();
  });

  test("returns 400 when prompt is missing", async () => {
    const res = await handleApiRequest(post("/api/v1/generate/skill", {}), ctx);
    expect(res!.status).toBe(400);
  });
});

describe("POST /api/v1/generate/agent (via GenerationService)", () => {
  let ctx: ApiContext;

  beforeEach(() => { ctx = buildCtx(); });

  test("returns 201 with agent fields", async () => {
    sdkYields({
      name: "Security Auditor",
      description: "Audits code.",
      systemPrompt: "You are a security expert.",
      model: "sonnet",
      icon: "shield",
      color: "red",
      matchedSkillIds: [],
      matchedMCPIds: [],
    });
    const res = await handleApiRequest(post("/api/v1/generate/agent", { prompt: "a security auditor" }), ctx);
    expect(res!.status).toBe(201);
    const body = await res!.json();
    expect(body.name).toBe("Security Auditor");
    expect(body.icon).toBe("shield");
  });

  test("falls back to cpu icon for unrecognized SF Symbol", async () => {
    sdkYields({ name: "Bot", description: "A bot.", systemPrompt: "Be a bot.", model: "sonnet", icon: "made-up-icon", color: "blue", matchedSkillIds: [], matchedMCPIds: [] });
    const res = await handleApiRequest(post("/api/v1/generate/agent", { prompt: "a bot" }), ctx);
    expect(res!.status).toBe(201);
    const body = await res!.json();
    expect(body.icon).toBe("cpu");
  });

  test("returns 400 when prompt is missing", async () => {
    const res = await handleApiRequest(post("/api/v1/generate/agent", {}), ctx);
    expect(res!.status).toBe(400);
  });
});
