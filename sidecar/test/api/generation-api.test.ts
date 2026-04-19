/**
 * API tests for POST /api/v1/agents/generate.
 *
 * Tests the handleGenerateAgent REST handler through handleApiRequest directly
 * (no real HTTP server). The Anthropic SDK is mocked via bun:test mock.module
 * so no real LLM calls are made.
 *
 * IMPORTANT: mock.module must be called before importing the module under test.
 */
import { mock, describe, test, expect, beforeEach } from "bun:test";

// ─── Mock @anthropic-ai/sdk before any import of api-router ──────────────────

type MockCreate = (opts: any) => Promise<any>;
let mockCreate: MockCreate = async () => ({
  content: [{ type: "text", text: JSON.stringify({
    name: "Security Auditor",
    description: "Audits code for security issues.",
    systemPrompt: "You are a security expert.",
    model: "sonnet",
    icon: "shield",
    color: "red",
    matchedSkillIds: [],
    matchedMCPIds: [],
  }) }],
});

mock.module("@anthropic-ai/sdk", () => ({
  default: class MockAnthropic {
    messages = {
      create: async (opts: any) => mockCreate(opts),
    };
  },
}));

// ─── Imports (after mock) ─────────────────────────────────────────────────────

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

// ─── Test helpers ─────────────────────────────────────────────────────────────

function buildApiCtx(): ApiContext {
  const toolCtx: ToolContext = {
    blackboard: new BlackboardStore(`gen-api-${Date.now()}-${Math.random()}`),
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
  };
  const mockSessionManager = {
    listSessions: () => Array.from(toolCtx.sessions.list()),
    sendMessage: async () => {},
    pauseSession: async () => {},
    resumeSession: async () => {},
    forkSession: async () => {},
    spawnAutonomous: async (id: string) => ({ sessionId: id }),
    updateSessionMode: () => {},
    answerQuestion: async () => false,
    answerConfirmation: async () => false,
    buildQueryOptionsForTesting: () => ({}),
    updateSessionCwd: () => {},
    bulkResume: async () => {},
  } as any;
  return {
    toolCtx,
    sessionManager: mockSessionManager,
    sseManager: new SseManager(),
    webhookManager: new WebhookManager(),
  };
}

async function postGenerate(body: unknown, ctx: ApiContext): Promise<{ status: number; body: any }> {
  const res = await handleApiRequest(
    new Request("http://test/api/v1/agents/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }),
    ctx,
  );
  if (!res) return { status: 0, body: null };
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("POST /api/v1/agents/generate", () => {
  let ctx: ApiContext;

  beforeEach(() => {
    ctx = buildApiCtx();
    // Restore default mock returning a valid spec
    mockCreate = async () => ({
      content: [{ type: "text", text: JSON.stringify({
        name: "Security Auditor",
        description: "Audits code for security issues.",
        systemPrompt: "You are a security expert. Review code for vulnerabilities.",
        model: "sonnet",
        icon: "shield",
        color: "red",
        matchedSkillIds: [],
        matchedMCPIds: [],
      }) }],
    });
  });

  test("returns 201 and spec with required fields when given a valid prompt", async () => {
    const { status, body } = await postGenerate({ prompt: "A security expert agent" }, ctx);
    expect(status).toBe(201);
    expect(body.name).toBeDefined();
    expect(body.systemPrompt).toBeDefined();
    expect(body.icon).toBeDefined();
    expect(body.color).toBeDefined();
  });

  test("returns 201 with correct spec values from mock", async () => {
    const { status, body } = await postGenerate({ prompt: "A security expert agent" }, ctx);
    expect(status).toBe(201);
    expect(body.name).toBe("Security Auditor");
    expect(body.icon).toBe("shield");
    expect(body.color).toBe("red");
    expect(body.model).toBe("sonnet");
  });

  test("returns 400 when prompt is missing", async () => {
    const { status, body } = await postGenerate({}, ctx);
    expect(status).toBe(400);
    expect(body.error).toBe("invalid_request");
    expect(body.message).toContain("prompt");
  });

  test("returns 400 when prompt is empty string", async () => {
    const { status, body } = await postGenerate({ prompt: "" }, ctx);
    expect(status).toBe(400);
    expect(body.error).toBe("invalid_request");
  });

  test("returns 400 when body is missing entirely", async () => {
    const res = await handleApiRequest(
      new Request("http://test/api/v1/agents/generate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "not json",
      }),
      ctx,
    );
    expect(res).not.toBeNull();
    expect(res!.status).toBe(400);
  });

  test("returns 500 when Claude returns non-JSON text", async () => {
    mockCreate = async () => ({
      content: [{ type: "text", text: "I cannot generate that agent for you." }],
    });
    const { status, body } = await postGenerate({ prompt: "some agent" }, ctx);
    expect(status).toBe(500);
    expect(body.error).toBeDefined();
  });

  test("returns 500 when Claude returns no text block", async () => {
    mockCreate = async () => ({ content: [] });
    const { status, body } = await postGenerate({ prompt: "some agent" }, ctx);
    expect(status).toBe(500);
    expect(body.error).toBe("internal_error");
  });

  test("defaults invalid icon to 'cpu'", async () => {
    mockCreate = async () => ({
      content: [{ type: "text", text: JSON.stringify({
        name: "My Agent",
        description: "Does things.",
        systemPrompt: "You help.",
        model: "sonnet",
        icon: "not-valid-icon",
        color: "blue",
        matchedSkillIds: [],
        matchedMCPIds: [],
      }) }],
    });
    const { status, body } = await postGenerate({ prompt: "some agent" }, ctx);
    expect(status).toBe(201);
    expect(body.icon).toBe("cpu");
  });

  test("defaults invalid color to 'blue'", async () => {
    mockCreate = async () => ({
      content: [{ type: "text", text: JSON.stringify({
        name: "My Agent",
        description: "Does things.",
        systemPrompt: "You help.",
        model: "sonnet",
        icon: "cpu",
        color: "chartreuse",
        matchedSkillIds: [],
        matchedMCPIds: [],
      }) }],
    });
    const { status, body } = await postGenerate({ prompt: "some agent" }, ctx);
    expect(status).toBe(201);
    expect(body.color).toBe("blue");
  });

  test("handles JSON wrapped in markdown code fences", async () => {
    const spec = {
      name: "Fenced Agent",
      description: "Testing code fences.",
      systemPrompt: "You are helpful.",
      model: "sonnet",
      icon: "gear",
      color: "green",
      matchedSkillIds: [],
      matchedMCPIds: [],
    };
    mockCreate = async () => ({
      content: [{ type: "text", text: "```json\n" + JSON.stringify(spec) + "\n```" }],
    });
    const { status, body } = await postGenerate({ prompt: "some agent" }, ctx);
    expect(status).toBe(201);
    expect(body.name).toBe("Fenced Agent");
    expect(body.icon).toBe("gear");
  });

  test("passes prompt to the Anthropic SDK", async () => {
    let capturedMessages: any[] = [];
    mockCreate = async (opts: any) => {
      capturedMessages = opts.messages;
      return {
        content: [{ type: "text", text: JSON.stringify({
          name: "Agent", systemPrompt: "Help.", model: "sonnet", icon: "cpu", color: "blue",
          matchedSkillIds: [], matchedMCPIds: [],
        }) }],
      };
    };
    await postGenerate({ prompt: "Build me a code review agent" }, ctx);
    expect(capturedMessages).toHaveLength(1);
    expect(capturedMessages[0].content).toBe("Build me a code review agent");
  });
});
