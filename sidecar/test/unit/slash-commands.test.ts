/**
 * Unit tests for slash-command-related store operations:
 * ConversationStore.clearMessages and SessionRegistry.updateConfig
 * (used by conversation.clear, session.updateModel, session.updateEffort handlers).
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import type { ConversationSummaryWire, MessageWire } from "../../src/stores/conversation-store.js";
import type { AgentConfig } from "../../src/types.js";

const makeConv = (id: string): ConversationSummaryWire => ({
  id, topic: "Test", lastMessageAt: "2026-01-01T00:00:00Z",
  lastMessagePreview: "", unread: false, participants: [],
  projectId: null, projectName: null, workingDirectory: null,
});
const makeMsg = (id: string, text: string): MessageWire => ({
  id, text, type: "text", senderParticipantId: null,
  timestamp: "2026-01-01T00:00:00Z", isStreaming: false,
});

const baseConfig: AgentConfig = {
  name: "TestAgent",
  systemPrompt: "You are helpful.",
  allowedTools: ["Read"],
  mcpServers: [],
  model: "claude-sonnet-4-6",
  workingDirectory: "/tmp",
  skills: [],
};

// ─── ConversationStore.clearMessages ────────────────────────────────

describe("ConversationStore.clearMessages", () => {
  let store: ConversationStore;

  beforeEach(() => {
    store = new ConversationStore();
    store.sync([makeConv("conv-1"), makeConv("conv-2")]);
    store.appendMessage("conv-1", makeMsg("m1", "Hello"));
    store.appendMessage("conv-1", makeMsg("m2", "World"));
    store.appendMessage("conv-2", makeMsg("m3", "Other"));
  });

  test("removes all messages for the target conversation", () => {
    expect(store.getMessages("conv-1")).toHaveLength(2);
    store.clearMessages("conv-1");
    expect(store.getMessages("conv-1")).toHaveLength(0);
  });

  test("does not affect messages from other conversations", () => {
    store.clearMessages("conv-1");
    expect(store.getMessages("conv-2")).toHaveLength(1);
  });

  test("idempotent — clearing twice does not throw", () => {
    store.clearMessages("conv-1");
    expect(() => store.clearMessages("conv-1")).not.toThrow();
    expect(store.getMessages("conv-1")).toHaveLength(0);
  });

  test("clearing unknown conversationId does not throw", () => {
    expect(() => store.clearMessages("does-not-exist")).not.toThrow();
  });

  test("new messages can be appended after clear", () => {
    store.clearMessages("conv-1");
    store.appendMessage("conv-1", makeMsg("m-new", "Fresh start"));
    expect(store.getMessages("conv-1")).toHaveLength(1);
    expect(store.getMessages("conv-1")[0].text).toBe("Fresh start");
  });
});

// ─── SessionRegistry.updateConfig — model update ────────────────────

describe("SessionRegistry.updateConfig — model override", () => {
  let registry: SessionRegistry;

  beforeEach(() => {
    registry = new SessionRegistry();
    registry.create("sess-1", { ...baseConfig });
  });

  test("updates model on existing session config", () => {
    registry.updateConfig("sess-1", { model: "claude-opus-4-7" });
    expect(registry.getConfig("sess-1")?.model).toBe("claude-opus-4-7");
  });

  test("preserves other fields after model update", () => {
    registry.updateConfig("sess-1", { model: "claude-haiku-4-5" });
    const cfg = registry.getConfig("sess-1");
    expect(cfg?.name).toBe("TestAgent");
    expect(cfg?.workingDirectory).toBe("/tmp");
  });

  test("no-op on missing session", () => {
    expect(() =>
      registry.updateConfig("does-not-exist", { model: "claude-opus-4-7" })
    ).not.toThrow();
  });

  test("can update model multiple times", () => {
    registry.updateConfig("sess-1", { model: "claude-opus-4-7" });
    registry.updateConfig("sess-1", { model: "claude-haiku-4-5" });
    expect(registry.getConfig("sess-1")?.model).toBe("claude-haiku-4-5");
  });
});

// ─── SessionRegistry.updateConfig — effort (maxThinkingTokens) ──────

describe("SessionRegistry.updateConfig — effort levels", () => {
  let registry: SessionRegistry;

  beforeEach(() => {
    registry = new SessionRegistry();
    registry.create("sess-2", { ...baseConfig });
  });

  test("low effort sets maxThinkingTokens to 0", () => {
    registry.updateConfig("sess-2", { maxThinkingTokens: 0 });
    expect(registry.getConfig("sess-2")?.maxThinkingTokens).toBe(0);
  });

  test("medium effort sets maxThinkingTokens to 8000", () => {
    registry.updateConfig("sess-2", { maxThinkingTokens: 8_000 });
    expect(registry.getConfig("sess-2")?.maxThinkingTokens).toBe(8_000);
  });

  test("high effort sets maxThinkingTokens to 32000", () => {
    registry.updateConfig("sess-2", { maxThinkingTokens: 32_000 });
    expect(registry.getConfig("sess-2")?.maxThinkingTokens).toBe(32_000);
  });

  test("max effort sets maxThinkingTokens to 100000", () => {
    registry.updateConfig("sess-2", { maxThinkingTokens: 100_000 });
    expect(registry.getConfig("sess-2")?.maxThinkingTokens).toBe(100_000);
  });

  test("effort update does not affect model", () => {
    registry.updateConfig("sess-2", { maxThinkingTokens: 32_000 });
    expect(registry.getConfig("sess-2")?.model).toBe("claude-sonnet-4-6");
  });
});
