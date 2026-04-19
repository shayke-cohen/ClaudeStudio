/**
 * API tests for multi-model agent and group endpoints.
 *
 * Tests GET /api/v1/agents and GET /api/v1/agents/:name with agents
 * that have non-default providers (codex, foundation).
 *
 * Boots a real HttpServer on a random ephemeral port.
 *
 * Usage: bun test test/api/groups-api.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { handleApiRequest } from "../../src/api-router.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { SseManager } from "../../src/sse-manager.js";
import { WebhookManager } from "../../src/webhook-manager.js";
import type { ApiContext } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";

const BASE = "http://localhost/api/v1";

function makeAgentConfig(overrides: Partial<AgentConfig> = {}): AgentConfig {
  return {
    name: "Agent",
    systemPrompt: "You are helpful.",
    allowedTools: [],
    mcpServers: [],
    provider: "claude",
    model: "sonnet",
    workingDirectory: "/tmp",
    skills: [],
    maxTurns: 30,
    maxBudget: 3.0,
    ...overrides,
  };
}

function makeContext(agentDefs: Map<string, AgentConfig>): ApiContext {
  const toolCtx: ToolContext = {
    blackboard: new BlackboardStore(`groups-api-${Date.now()}`),
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
    broadcast: (_: SidecarEvent) => {},
    agentDefinitions: agentDefs,
    spawnSession: async (sessionId) => ({ sessionId }),
  };

  return {
    sessionManager: {
      listSessions: () => [],
    } as any,
    toolCtx,
    sseManager: new SseManager(),
    webhookManager: new WebhookManager(),
  };
}

async function apiRequest(
  ctx: ApiContext,
  path: string,
  method = "GET",
  body?: unknown
): Promise<Response> {
  const req = new Request(`${BASE}${path}`, {
    method,
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  return handleApiRequest(req, ctx);
}

// ─── GET /api/v1/agents ──────────────────────────────────────────────

describe("GET /api/v1/agents — multi-model group agents", () => {
  test("returns empty array when no agents defined", async () => {
    const ctx = makeContext(new Map());
    const res = await apiRequest(ctx, "/agents");
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.agents).toEqual([]);
  });

  test("returns codex agent with provider field", async () => {
    const defs = new Map<string, AgentConfig>([
      [
        "Coder (Codex)",
        makeAgentConfig({ name: "Coder (Codex)", provider: "codex", model: "gpt-5-codex" }),
      ],
    ]);
    const ctx = makeContext(defs);

    const res = await apiRequest(ctx, "/agents");
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    const agent = body.agents.find((a: any) => a.name === "Coder (Codex)");
    expect(agent).toBeDefined();
    expect(agent.provider).toBe("codex");
    expect(agent.model).toBe("gpt-5-codex");
  });

  test("returns foundation agent with provider field", async () => {
    const defs = new Map<string, AgentConfig>([
      [
        "Coder (Local)",
        makeAgentConfig({ name: "Coder (Local)", provider: "foundation", model: "foundation.system" }),
      ],
    ]);
    const ctx = makeContext(defs);

    const res = await apiRequest(ctx, "/agents");
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    const agent = body.agents.find((a: any) => a.name === "Coder (Local)");
    expect(agent).toBeDefined();
    expect(agent.provider).toBe("foundation");
    expect(agent.model).toBe("foundation.system");
  });

  test("lists all Dual Coder Debate agents with their providers", async () => {
    const defs = new Map<string, AgentConfig>([
      ["Coder (Codex)", makeAgentConfig({ name: "Coder (Codex)", provider: "codex", model: "gpt-5-codex" })],
      ["Coder", makeAgentConfig({ name: "Coder", provider: "claude", model: "opus" })],
      ["Reviewer", makeAgentConfig({ name: "Reviewer", provider: "claude", model: "sonnet" })],
    ]);
    const ctx = makeContext(defs);

    const res = await apiRequest(ctx, "/agents");
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.agents.length).toBe(3);

    const byName = Object.fromEntries(body.agents.map((a: any) => [a.name, a]));
    expect(byName["Coder (Codex)"].provider).toBe("codex");
    expect(byName["Coder"].provider).toBe("claude");
    expect(byName["Reviewer"].provider).toBe("claude");
  });

  test("lists all Cost-Tiered Squad agents with distinct model tiers", async () => {
    const defs = new Map<string, AgentConfig>([
      ["Orchestrator", makeAgentConfig({ name: "Orchestrator", provider: "claude", model: "opus" })],
      ["Coder (Sonnet)", makeAgentConfig({ name: "Coder (Sonnet)", provider: "claude", model: "sonnet" })],
      ["Tester (Haiku)", makeAgentConfig({ name: "Tester (Haiku)", provider: "claude", model: "haiku" })],
    ]);
    const ctx = makeContext(defs);

    const res = await apiRequest(ctx, "/agents");
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    const models = body.agents.map((a: any) => a.model);
    expect(models).toContain("opus");
    expect(models).toContain("sonnet");
    expect(models).toContain("haiku");
  });
});

// ─── GET /api/v1/agents/:name ────────────────────────────────────────

describe("GET /api/v1/agents/:name — individual multi-model agents", () => {
  test("returns full config for Coder (Codex) with codex provider", async () => {
    const defs = new Map<string, AgentConfig>([
      ["Coder (Codex)", makeAgentConfig({
        name: "Coder (Codex)",
        provider: "codex",
        model: "gpt-5-codex",
        maxTurns: 50,
        maxBudget: 5.0,
      })],
    ]);
    const ctx = makeContext(defs);

    const res = await apiRequest(ctx, "/agents/Coder%20(Codex)");
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.name).toBe("Coder (Codex)");
    expect(body.provider).toBe("codex");
    expect(body.model).toBe("gpt-5-codex");
    expect(body.maxTurns).toBe(50);
    expect(body.maxBudget).toBe(5.0);
  });

  test("returns full config for Attacker with codex provider", async () => {
    const defs = new Map<string, AgentConfig>([
      ["Attacker", makeAgentConfig({
        name: "Attacker",
        provider: "codex",
        model: "gpt-5-codex",
        maxTurns: 30,
        maxBudget: 3.0,
      })],
    ]);
    const ctx = makeContext(defs);

    const res = await apiRequest(ctx, "/agents/Attacker");
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.provider).toBe("codex");
    expect(body.model).toBe("gpt-5-codex");
  });

  test("returns full config for Coder (Local) with foundation provider", async () => {
    const defs = new Map<string, AgentConfig>([
      ["Coder (Local)", makeAgentConfig({
        name: "Coder (Local)",
        provider: "foundation",
        model: "foundation.system",
        maxTurns: 20,
        maxBudget: 0,
      })],
    ]);
    const ctx = makeContext(defs);

    const res = await apiRequest(ctx, "/agents/Coder%20(Local)");
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.provider).toBe("foundation");
    expect(body.model).toBe("foundation.system");
    expect(body.maxTurns).toBe(20);
  });

  test("returns 404 for unknown multi-model agent name", async () => {
    const ctx = makeContext(new Map());
    const res = await apiRequest(ctx, "/agents/Nonexistent%20Agent");
    expect(res.status).toBe(404);
    const body = (await res.json()) as any;
    expect(body.error).toBe("agent_not_found");
  });

  test("claude agent without explicit provider returns 'claude' in response", async () => {
    const defs = new Map<string, AgentConfig>([
      ["Coder", makeAgentConfig({ name: "Coder", provider: undefined, model: "opus" })],
    ]);
    const ctx = makeContext(defs);

    const res = await apiRequest(ctx, "/agents/Coder");
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    // API defaults undefined provider to "claude"
    expect(body.provider).toBe("claude");
  });
});

// ─── Provider field presence across all new agent types ─────────────

describe("provider field — new multi-model agent types", () => {
  const NEW_AGENTS: Array<{ name: string; provider: string; model: string }> = [
    { name: "Coder (Codex)", provider: "codex", model: "gpt-5-codex" },
    { name: "Attacker", provider: "codex", model: "gpt-5-codex" },
    { name: "Coder (Sonnet)", provider: "claude", model: "sonnet" },
    { name: "Tester (Haiku)", provider: "claude", model: "haiku" },
    { name: "Coder (Local)", provider: "foundation", model: "foundation.system" },
  ];

  for (const { name, provider, model } of NEW_AGENTS) {
    test(`${name} exposes correct provider="${provider}" and model="${model}" via API`, async () => {
      const defs = new Map<string, AgentConfig>([
        [name, makeAgentConfig({ name, provider, model })],
      ]);
      const ctx = makeContext(defs);

      const encodedName = encodeURIComponent(name);
      const res = await apiRequest(ctx, `/agents/${encodedName}`);
      expect(res.status).toBe(200);
      const body = (await res.json()) as any;
      expect(body.provider).toBe(provider);
      expect(body.model).toBe(model);
    });
  }
});
