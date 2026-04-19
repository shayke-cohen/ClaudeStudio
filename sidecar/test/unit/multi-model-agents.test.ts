/**
 * Unit tests for multi-model agent configuration.
 *
 * Verifies that agents with different providers (codex, foundation, mlx)
 * are registered, retrieved, and normalized correctly through the
 * SessionRegistry and SessionManager without hitting real runtimes.
 *
 * Usage: bun test test/unit/multi-model-agents.test.ts
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import type { AgentConfig } from "../../src/types.js";

function makeConfig(overrides: Partial<AgentConfig> = {}): AgentConfig {
  return {
    name: "Test Agent",
    systemPrompt: "You are a test agent.",
    allowedTools: [],
    mcpServers: [],
    provider: "claude",
    model: "sonnet",
    workingDirectory: "/tmp",
    skills: [],
    ...overrides,
  };
}

// ─── SessionRegistry with multi-provider configs ────────────────────

describe("SessionRegistry — multi-provider agents", () => {
  let registry: SessionRegistry;

  beforeEach(() => {
    registry = new SessionRegistry();
  });

  test("creates a codex agent session", () => {
    const config = makeConfig({
      name: "Coder (Codex)",
      provider: "codex",
      model: "gpt-5.4",
    });
    const state = registry.create("sess-codex-1", config);
    expect(state).toBeDefined();
    // SessionState stores the resolved provider
    expect(state.provider).toBe("codex");
    expect(state.agentName).toBe("Coder (Codex)");
    // AgentConfig is accessible via getConfig
    const cfg = registry.getConfig("sess-codex-1");
    expect(cfg!.provider).toBe("codex");
    expect(cfg!.model).toBe("gpt-5.4");
  });

  test("creates a foundation (local) agent session", () => {
    const config = makeConfig({
      name: "Coder (Local)",
      provider: "foundation",
      model: "foundation.system",
    });
    const state = registry.create("sess-local-1", config);
    expect(state.provider).toBe("foundation");
    const cfg = registry.getConfig("sess-local-1")!;
    expect(cfg.provider).toBe("foundation");
    expect(cfg.model).toBe("foundation.system");
  });

  test("creates a haiku agent session", () => {
    const config = makeConfig({ name: "Tester (Haiku)", provider: "claude", model: "haiku" });
    registry.create("sess-haiku-1", config);
    const cfg = registry.getConfig("sess-haiku-1")!;
    expect(cfg.model).toBe("haiku");
  });

  test("agents without explicit provider resolve to claude in SessionState", () => {
    const config = makeConfig({ provider: undefined });
    const state = registry.create("sess-no-provider", config);
    // SessionRegistry normalizes undefined provider to "claude" in SessionState
    expect(state.provider).toBe("claude");
  });

  test("multiple sessions with different providers coexist independently", () => {
    const codexConfig = makeConfig({ name: "Coder (Codex)", provider: "codex", model: "gpt-5.4" });
    const claudeConfig = makeConfig({ name: "Coder", provider: "claude", model: "opus" });
    const localConfig = makeConfig({ name: "Coder (Local)", provider: "foundation", model: "foundation.system" });

    registry.create("sess-1", codexConfig);
    registry.create("sess-2", claudeConfig);
    registry.create("sess-3", localConfig);

    expect(registry.getConfig("sess-1")!.provider).toBe("codex");
    expect(registry.getConfig("sess-2")!.provider).toBe("claude");
    expect(registry.getConfig("sess-3")!.provider).toBe("foundation");
  });

  test("list returns all sessions with their provider", () => {
    registry.create("s1", makeConfig({ provider: "codex", model: "gpt-5.4" }));
    registry.create("s2", makeConfig({ provider: "claude", model: "opus" }));

    const all = registry.list();
    expect(all.length).toBeGreaterThanOrEqual(2);
  });

  test("removing a session does not affect others", () => {
    registry.create("keep", makeConfig({ provider: "claude", model: "opus" }));
    registry.create("remove-me", makeConfig({ provider: "codex", model: "gpt-5.4" }));

    registry.remove("remove-me");

    expect(registry.get("keep")).toBeDefined();
    expect(registry.get("remove-me")).toBeUndefined();
  });
});

// ─── Multi-model group agent definition map ─────────────────────────

describe("agentDefinitions map — multi-model group membership", () => {
  test("dual coder debate agents have distinct providers", () => {
    const definitions = new Map<string, AgentConfig>([
      ["Coder (Codex)", makeConfig({ name: "Coder (Codex)", provider: "codex", model: "gpt-5.4" })],
      ["Coder", makeConfig({ name: "Coder", provider: "claude", model: "opus" })],
      ["Reviewer", makeConfig({ name: "Reviewer", provider: "claude", model: "sonnet" })],
    ]);

    const codexCoder = definitions.get("Coder (Codex)")!;
    const claudeCoder = definitions.get("Coder")!;
    const reviewer = definitions.get("Reviewer")!;

    expect(codexCoder.provider).toBe("codex");
    expect(claudeCoder.provider).toBe("claude");
    expect(reviewer.provider).toBe("claude");
    expect(codexCoder.model).toBe("gpt-5.4");
    expect(claudeCoder.model).toBe("opus");
    expect(reviewer.model).toBe("sonnet");
  });

  test("cost-tiered squad uses three different Claude model tiers", () => {
    const definitions = new Map<string, AgentConfig>([
      ["Orchestrator", makeConfig({ name: "Orchestrator", provider: "claude", model: "opus" })],
      ["Coder (Sonnet)", makeConfig({ name: "Coder (Sonnet)", provider: "claude", model: "sonnet" })],
      ["Tester (Haiku)", makeConfig({ name: "Tester (Haiku)", provider: "claude", model: "haiku" })],
    ]);

    const models = [...definitions.values()].map((c) => c.model);
    expect(models).toContain("opus");
    expect(models).toContain("sonnet");
    expect(models).toContain("haiku");
    // All three should be distinct
    expect(new Set(models).size).toBe(3);
  });

  test("local first group uses foundation for coder and claude for reviewer", () => {
    const definitions = new Map<string, AgentConfig>([
      ["Coder (Local)", makeConfig({ name: "Coder (Local)", provider: "foundation", model: "foundation.system" })],
      ["Reviewer", makeConfig({ name: "Reviewer", provider: "claude", model: "sonnet" })],
    ]);

    expect(definitions.get("Coder (Local)")!.provider).toBe("foundation");
    expect(definitions.get("Reviewer")!.provider).toBe("claude");
  });

  test("red team attacker uses codex provider", () => {
    const definitions = new Map<string, AgentConfig>([
      ["Coder", makeConfig({ name: "Coder", provider: "claude", model: "opus" })],
      ["Attacker", makeConfig({ name: "Attacker", provider: "codex", model: "gpt-5.4" })],
      ["Tester", makeConfig({ name: "Tester", provider: "claude", model: "sonnet" })],
    ]);

    expect(definitions.get("Attacker")!.provider).toBe("codex");
    expect(definitions.get("Attacker")!.model).toBe("gpt-5.4");
  });
});
