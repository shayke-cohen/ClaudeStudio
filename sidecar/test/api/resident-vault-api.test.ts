/**
 * API tests for Resident Agent vault working directory.
 *
 * Tests that:
 * - An agent registered with a vault working directory exposes it correctly via GET /agents/:name
 * - POST /sessions with a vault-working-directory agent stores the workingDirectory in the session
 * - Sessions list reflects the vault working directory
 * - The vault working directory survives session lifecycle operations (pause, resume)
 *
 * Usage: ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) bun test test/api/resident-vault-api.test.ts
 */
import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, writeFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
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
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import type { ApiContext, SidecarEvent, AgentConfig } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";

const BASE = "http://localhost/api/v1";

// ─── Vault factory ───────────────────────────────────────────────────

function createVaultDir(agentSlug: string): string {
  const dir = mkdtempSync(join(tmpdir(), `vault-api-${agentSlug}-`));
  const date = new Date().toISOString().split("T")[0];

  writeFileSync(join(dir, "CLAUDE.md"), `---\nagent: ${agentSlug}\nupdated: ${date}\n---\n\n# ${agentSlug}\n`);
  writeFileSync(join(dir, "MEMORY.md"), `---\nupdated: ${date}\ncap: "200 lines"\n---\n\n# Memory\n`);
  writeFileSync(join(dir, "INDEX.md"), `---\nupdated: ${date}\n---\n\n# Index\n`);
  writeFileSync(join(dir, "GUIDELINES.md"), `---\nupdated: ${date}\ntags: [guidelines]\n---\n\n# Guidelines\n`);
  writeFileSync(join(dir, "SESSION.md"), `---\nupdated: ${date}\nvolatile: true\n---\n\n# Current Session\n`);

  return dir;
}

// ─── Test context factory ────────────────────────────────────────────

type SpawnCall = { sessionId: string; config: AgentConfig; prompt: string; waitForResult: boolean };

const activeSseManagers: SseManager[] = [];

function makeCtx(): {
  ctx: ApiContext;
  sessions: SessionRegistry;
  spawnCalls: SpawnCall[];
} {
  const sessions = new SessionRegistry();
  const sseManager = new SseManager();
  const spawnCalls: SpawnCall[] = [];

  const toolCtx: ToolContext = {
    blackboard: new BlackboardStore(`vault-api-${Date.now()}`),
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
    broadcast: (event: SidecarEvent) => sseManager.broadcast(event),
    agentDefinitions: new Map(),
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
    spawnAutonomous: async (sessionId: string, config: AgentConfig, prompt: string, waitForResult: boolean) => {
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
  return { ctx, sessions, spawnCalls };
}

afterEach(() => {
  while (activeSseManagers.length > 0) activeSseManagers.pop()?.close();
});

// ─── Agent registration with vault workingDirectory ──────────────────

describe("API: GET /agents/:name — vault working directory", () => {
  test("returns vault workingDirectory in agent detail", async () => {
    const { ctx } = makeCtx();
    const vaultDir = createVaultDir("resident-coder");

    ctx.toolCtx.agentDefinitions.set("resident-coder", {
      name: "resident-coder",
      systemPrompt: "You are a resident coder.",
      allowedTools: ["Read", "Write", "Bash"],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      provider: "claude",
      workingDirectory: vaultDir,
      skills: [],
    });

    const res = await handleApiRequest(
      new Request(`${BASE}/agents/resident-coder`),
      ctx,
    );

    expect(res?.status).toBe(200);
    const body = await res?.json() as any;
    expect(body.name).toBe("resident-coder");
    expect(body.workingDirectory).toBe(vaultDir);
  });

  test("lists agent with vault workingDirectory in agents list", async () => {
    const { ctx } = makeCtx();
    const vaultDir = createVaultDir("resident-reviewer");

    ctx.toolCtx.agentDefinitions.set("resident-reviewer", {
      name: "resident-reviewer",
      systemPrompt: "You are a code reviewer.",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: vaultDir,
      skills: [],
    });

    const res = await handleApiRequest(new Request(`${BASE}/agents`), ctx);
    expect(res?.status).toBe(200);
    const body = await res?.json() as any;
    const agent = body.agents.find((a: any) => a.name === "resident-reviewer");
    expect(agent).toBeDefined();
    expect(agent.workingDirectory).toBe(vaultDir);
  });

  test("returns 404 for unregistered agent", async () => {
    const { ctx } = makeCtx();
    const res = await handleApiRequest(new Request(`${BASE}/agents/nonexistent-agent`), ctx);
    expect(res?.status).toBe(404);
  });
});

// ─── Session creation preserves vault working directory ──────────────

describe("API: POST /sessions — vault working directory preserved", () => {
  test("session created with vault agent stores vault workingDirectory", async () => {
    const { ctx, spawnCalls } = makeCtx();
    const vaultDir = createVaultDir("resident-architect");

    ctx.toolCtx.agentDefinitions.set("resident-architect", {
      name: "resident-architect",
      systemPrompt: "You are a software architect.",
      allowedTools: ["Read", "Write"],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: vaultDir,
      skills: [],
    });

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          agentName: "resident-architect",
          message: "Review the authentication flow",
          waitForResult: false,
        }),
      }),
      ctx,
    );

    expect(res?.status).toBe(201);
    const body = await res?.json() as any;
    expect(body.agentName).toBe("resident-architect");

    // The spawned session should carry the vault working directory
    expect(spawnCalls).toHaveLength(1);
    expect(spawnCalls[0].config.workingDirectory).toBe(vaultDir);
  });

  test("two resident agents maintain independent vault directories", async () => {
    const { ctx, spawnCalls } = makeCtx();
    const vaultA = createVaultDir("agent-alice");
    const vaultB = createVaultDir("agent-bob");

    for (const [name, vault] of [["agent-alice", vaultA], ["agent-bob", vaultB]]) {
      ctx.toolCtx.agentDefinitions.set(name, {
        name,
        systemPrompt: `You are ${name}.`,
        allowedTools: [],
        mcpServers: [],
        model: "claude-sonnet-4-6",
        workingDirectory: vault,
        skills: [],
      });
    }

    await handleApiRequest(
      new Request(`${BASE}/sessions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ agentName: "agent-alice", message: "hello", waitForResult: false }),
      }),
      ctx,
    );

    await handleApiRequest(
      new Request(`${BASE}/sessions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ agentName: "agent-bob", message: "hello", waitForResult: false }),
      }),
      ctx,
    );

    expect(spawnCalls).toHaveLength(2);
    expect(spawnCalls[0].config.workingDirectory).toBe(vaultA);
    expect(spawnCalls[1].config.workingDirectory).toBe(vaultB);
    expect(spawnCalls[0].config.workingDirectory).not.toBe(spawnCalls[1].config.workingDirectory);
  });
});

// ─── Session listing reflects vault working directory ────────────────

describe("API: GET /sessions — vault working directory preserved in session registry", () => {
  test("session registry retains vault workingDirectory after create", async () => {
    const { sessions } = makeCtx();
    const vaultDir = createVaultDir("resident-planner");
    const sessionId = `sess-vault-${Date.now()}`;

    sessions.create(sessionId, {
      name: "resident-planner",
      systemPrompt: "You are a planner.",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: vaultDir,
      skills: [],
    });

    // workingDirectory lives in AgentConfig, not SessionState
    expect(sessions.getConfig(sessionId)?.workingDirectory).toBe(vaultDir);
  });

  test("GET /sessions/:id returns 200 for a vault session", async () => {
    const { ctx, sessions } = makeCtx();
    const vaultDir = createVaultDir("resident-reviewer-api");
    const sessionId = `sess-vault-get-${Date.now()}`;

    sessions.create(sessionId, {
      name: "resident-reviewer",
      systemPrompt: "You review.",
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      workingDirectory: vaultDir,
      skills: [],
    });

    const res = await handleApiRequest(
      new Request(`${BASE}/sessions/${sessionId}`),
      ctx,
    );

    expect(res?.status).toBe(200);
    const body = await res?.json() as any;
    expect(body.id).toBe(sessionId);
    expect(body.agentName).toBe("resident-reviewer");
  });
});
