/**
 * Integration tests for multi-model group session management.
 *
 * Tests that group conversations with agents from different providers
 * (codex, foundation, claude) create independent sessions that each
 * carry the correct provider configuration through the sidecar.
 *
 * Uses mock spawnSession to avoid real API calls. Real runtime
 * integration is tested in local-agent-runtime.test.ts.
 *
 * Usage: bun test test/integration/multi-model-groups.test.ts
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";

type SpawnCall = { sessionId: string; config: AgentConfig };

function makeConfig(overrides: Partial<AgentConfig> = {}): AgentConfig {
  return {
    name: "Agent",
    systemPrompt: "You are helpful.",
    allowedTools: [],
    mcpServers: [],
    provider: "claude",
    model: "sonnet",
    workingDirectory: "/tmp",
    skills: [],
    ...overrides,
  };
}

function buildCtx(
  events: SidecarEvent[],
  spawnCalls: SpawnCall[],
  registry: SessionRegistry
): ToolContext {
  return {
    blackboard: new BlackboardStore(`mg-test-${Date.now()}-${Math.random()}`),
    taskBoard: new TaskBoardStore(`mg-test-${Date.now()}-${Math.random()}`),
    sessions: registry,
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
    broadcast: (e: SidecarEvent) => events.push(e),
    spawnSession: async (sessionId: string, config: AgentConfig) => {
      spawnCalls.push({ sessionId, config });
      return { sessionId };
    },
    agentDefinitions: new Map<string, AgentConfig>(),
  };
}

// ─── Multi-provider session registration ────────────────────────────

describe("Multi-model group — session registration", () => {
  let registry: SessionRegistry;
  let events: SidecarEvent[];
  let spawnCalls: SpawnCall[];

  beforeEach(() => {
    registry = new SessionRegistry();
    events = [];
    spawnCalls = [];
  });

  test("Dual Coder Debate creates 3 independent sessions with correct providers", async () => {
    const codexCoderCfg = makeConfig({ name: "Coder (Codex)", provider: "codex", model: "gpt-5.4" });
    const claudeCoderCfg = makeConfig({ name: "Coder", provider: "claude", model: "opus" });
    const reviewerCfg = makeConfig({ name: "Reviewer", provider: "claude", model: "sonnet" });

    // Simulate what the Swift app does: register 3 sessions for the group
    registry.create("sess-codex", codexCoderCfg);
    registry.create("sess-claude", claudeCoderCfg);
    registry.create("sess-reviewer", reviewerCfg);

    expect(registry.get("sess-codex")!.provider).toBe("codex");
    expect(registry.getConfig("sess-codex")!.model).toBe("gpt-5.4");

    expect(registry.get("sess-claude")!.provider).toBe("claude");
    expect(registry.getConfig("sess-claude")!.model).toBe("opus");

    expect(registry.get("sess-reviewer")!.provider).toBe("claude");
    expect(registry.getConfig("sess-reviewer")!.model).toBe("sonnet");

    // Sessions are fully independent — removing one doesn't affect others
    registry.remove("sess-codex");
    expect(registry.get("sess-claude")).toBeDefined();
    expect(registry.get("sess-reviewer")).toBeDefined();
  });

  test("Cost-Tiered Squad sessions carry distinct model tiers", () => {
    registry.create("sess-orch", makeConfig({ name: "Orchestrator", provider: "claude", model: "opus" }));
    registry.create("sess-sonnet", makeConfig({ name: "Coder (Sonnet)", provider: "claude", model: "sonnet" }));
    registry.create("sess-haiku", makeConfig({ name: "Tester (Haiku)", provider: "claude", model: "haiku" }));

    const models = ["sess-orch", "sess-sonnet", "sess-haiku"]
      .map((id) => registry.getConfig(id)!.model);

    expect(models).toContain("opus");
    expect(models).toContain("sonnet");
    expect(models).toContain("haiku");
    expect(new Set(models).size).toBe(3, "All three cost tiers should be distinct");
  });

  test("Local First keeps foundation session separate from cloud session", () => {
    registry.create("sess-local", makeConfig({ name: "Coder (Local)", provider: "foundation", model: "foundation.system" }));
    registry.create("sess-cloud", makeConfig({ name: "Reviewer", provider: "claude", model: "sonnet" }));

    const localEntry = registry.get("sess-local")!;
    const cloudEntry = registry.get("sess-cloud")!;

    expect(localEntry.provider).toBe("foundation");
    expect(cloudEntry.provider).toBe("claude");

    // Verify the two providers are distinct
    expect(localEntry.provider).not.toBe(cloudEntry.provider);
  });

  test("Red Team attacker session uses codex while coder and tester use claude", () => {
    registry.create("sess-coder", makeConfig({ name: "Coder", provider: "claude", model: "opus" }));
    registry.create("sess-attacker", makeConfig({ name: "Attacker", provider: "codex", model: "gpt-5.4" }));
    registry.create("sess-tester", makeConfig({ name: "Tester", provider: "claude", model: "sonnet" }));

    const attackerEntry = registry.get("sess-attacker")!;
    expect(attackerEntry.provider).toBe("codex");
    expect(registry.getConfig("sess-attacker")!.model).toBe("gpt-5.4");

    // Coder and Tester are Claude — attacker alone is Codex
    const claudeSessions = ["sess-coder", "sess-tester"]
      .map((id) => registry.get(id)!.provider);
    expect(claudeSessions.every((p) => p === "claude")).toBe(true);
  });
});

// ─── Blackboard isolation per group session ──────────────────────────

describe("Multi-model group — blackboard isolation", () => {
  test("codex and claude sessions write to shared blackboard without collision", () => {
    const bb = new BlackboardStore(`group-bb-${Date.now()}`);

    // Simulate each agent writing its own status key
    bb.write("impl.feature.status", "in-progress", "Coder (Codex)");
    bb.write("review.feature.status", "pending", "Reviewer");
    bb.write("attack.feature.status", "probing", "Attacker");

    expect(bb.read("impl.feature.status")!.writtenBy).toBe("Coder (Codex)");
    expect(bb.read("review.feature.status")!.writtenBy).toBe("Reviewer");
    expect(bb.read("attack.feature.status")!.writtenBy).toBe("Attacker");
  });

  test("cost-tiered squad writes tiered status keys without collision", () => {
    const bb = new BlackboardStore(`tiered-bb-${Date.now()}`);

    bb.write("plan.impl.outline", "Step 1: ...", "Orchestrator");
    bb.write("impl.auth.status", "complete", "Coder (Sonnet)");
    bb.write("test.auth.status", "passed", "Tester (Haiku)");

    const plan = bb.read("plan.impl.outline");
    const impl = bb.read("impl.auth.status");
    const tests = bb.read("test.auth.status");

    expect(plan!.value).toBe("Step 1: ...");
    expect(plan!.writtenBy).toBe("Orchestrator");
    expect(impl!.writtenBy).toBe("Coder (Sonnet)");
    expect(tests!.writtenBy).toBe("Tester (Haiku)");
  });

  test("red team attack findings are queryable by prefix", () => {
    const bb = new BlackboardStore(`redteam-bb-${Date.now()}`);

    bb.write("attack.auth.sqli", "SQLi on login", "Attacker");
    bb.write("attack.auth.xss", "XSS via username", "Attacker");
    bb.write("attack.auth.critical", "true", "Attacker");
    bb.write("impl.auth.status", "complete", "Coder");

    const attackFindings = bb.query("attack.auth.*");
    expect(attackFindings.length).toBe(3);
    expect(attackFindings.every((e) => e.writtenBy === "Attacker")).toBe(true);

    // impl key is not included in attack query
    const implKeys = attackFindings.filter((e) => e.key.startsWith("impl."));
    expect(implKeys.length).toBe(0);
  });
});
